// lib/apps/website/website_deploy_service.dart
//
// One-click deployment — no browser required.
// Handles GitHub Pages and Cloudflare Pages via REST APIs.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'website_models.dart';
import 'website_exporter.dart';

// ─── Result type ──────────────────────────────────────────────────────────────

class DeployResult {
  final bool   success;
  final String message;
  final String liveUrl;
  final String cnameTarget;   // for manual DNS setup
  final String zoneId;        // CF zone ID if fetched

  const DeployResult({
    required this.success,
    required this.message,
    this.liveUrl     = '',
    this.cnameTarget = '',
    this.zoneId      = '',
  });

  factory DeployResult.err(String msg) =>
      DeployResult(success: false, message: msg);
}

// ─── DNS record model ─────────────────────────────────────────────────────────

class DnsRecord {
  final String type;
  final String host;
  final String value;
  final String ttl;
  const DnsRecord({
    required this.type,
    required this.host,
    required this.value,
    this.ttl = 'Automatic',
  });
}

List<DnsRecord> buildDnsRecords(String cnameTarget) {
  if (cnameTarget.isEmpty) return [];
  return [
    DnsRecord(type: 'CNAME', host: '@',   value: cnameTarget),
    DnsRecord(type: 'CNAME', host: 'www', value: cnameTarget),
  ];
}

// ─── GitHub Deploy Service ────────────────────────────────────────────────────

class GitHubDeployService {
  final String token;
  static const _api = 'https://api.github.com';
  GitHubDeployService(this.token);

  Map<String, String> get _h => {
    'Authorization': 'Bearer $token',
    'Accept':        'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'Content-Type':  'application/json',
  };

  Future<DeployResult> verifyToken() async {
    try {
      final res = await http.get(Uri.parse('$_api/user'), headers: _h);
      if (res.statusCode != 200) {
        return DeployResult.err(
          'Invalid GitHub token (${res.statusCode}).\n'
          'Create one at github.com/settings/tokens with repo + pages permissions.');
      }
      return DeployResult(
          success: true, message: jsonDecode(res.body)['login'] as String);
    } catch (e) {
      return DeployResult.err('Network error: $e');
    }
  }

  Future<DeployResult> _ensureRepo(String username, String repoName) async {
    final check = await http.get(
        Uri.parse('$_api/repos/$username/$repoName'), headers: _h);
    if (check.statusCode == 200) {
      return DeployResult(success: true, message: 'exists');
    }
    final create = await http.post(
      Uri.parse('$_api/user/repos'),
      headers: _h,
      body: jsonEncode({
        'name': repoName,
        'description': 'Church website — Church Plant Toolkit',
        'private': false,
        'auto_init': false,
      }),
    );
    if (create.statusCode == 201) {
      return DeployResult(success: true, message: 'created');
    }
    final msg = (jsonDecode(create.body)['errors'] as List?)
        ?.map((e) => e['message']).join(', ') ?? create.body;
    return DeployResult.err('Could not create repo: $msg');
  }

  Future<DeployResult> _pushFiles(
    String username,
    String repoName,
    Map<String, String> files,
  ) async {
    final base = '$_api/repos/$username/$repoName';

    // Get current HEAD sha if repo has commits
    String? baseSha;
    String? baseTreeSha;
    final refRes = await http.get(
        Uri.parse('$base/git/refs/heads/main'), headers: _h);
    if (refRes.statusCode == 200) {
      baseSha = jsonDecode(refRes.body)['object']['sha'] as String;
      final commitRes = await http.get(
          Uri.parse('$base/git/commits/$baseSha'), headers: _h);
      baseTreeSha = jsonDecode(commitRes.body)['tree']['sha'] as String;
    }

    // Create blobs
    final treeItems = <Map<String, dynamic>>[];
    for (final e in files.entries) {
      final blob = await http.post(
        Uri.parse('$base/git/blobs'),
        headers: _h,
        body: jsonEncode({
          'content':  base64Encode(utf8.encode(e.value)),
          'encoding': 'base64',
        }),
      );
      if (blob.statusCode != 201) {
        return DeployResult.err('Failed uploading ${e.key}');
      }
      treeItems.add({
        'path': e.key, 'mode': '100644', 'type': 'blob',
        'sha': jsonDecode(blob.body)['sha'],
      });
    }

    // Create tree
    final treeBody = <String, dynamic>{'tree': treeItems};
    if (baseTreeSha != null) treeBody['base_tree'] = baseTreeSha;

    final tree = await http.post(Uri.parse('$base/git/trees'),
        headers: _h, body: jsonEncode(treeBody));
    if (tree.statusCode != 201) return DeployResult.err('Tree creation failed');
    final treeSha = jsonDecode(tree.body)['sha'] as String;

    // Create commit
    final commitBody = <String, dynamic>{
      'message': 'Deploy via Church Plant Toolkit',
      'tree': treeSha,
    };
    if (baseSha != null) commitBody['parents'] = [baseSha];
    final commit = await http.post(Uri.parse('$base/git/commits'),
        headers: _h, body: jsonEncode(commitBody));
    if (commit.statusCode != 201) return DeployResult.err('Commit failed');
    final commitSha = jsonDecode(commit.body)['sha'] as String;

    // Update ref
    if (baseSha != null) {
      await http.patch(Uri.parse('$base/git/refs/heads/main'),
          headers: _h, body: jsonEncode({'sha': commitSha, 'force': true}));
    } else {
      await http.post(Uri.parse('$base/git/refs'),
          headers: _h,
          body: jsonEncode({'ref': 'refs/heads/main', 'sha': commitSha}));
    }
    return DeployResult(success: true, message: 'pushed');
  }

  Future<DeployResult> _enablePages(
    String username,
    String repoName,
    String? customDomain,
  ) async {
    final base = '$_api/repos/$username/$repoName';
    final check = await http.get(Uri.parse('$base/pages'), headers: _h);
    if (check.statusCode == 404) {
      final enable = await http.post(
        Uri.parse('$base/pages'),
        headers: _h,
        body: jsonEncode({'source': {'branch': 'main', 'path': '/'}}),
      );
      if (enable.statusCode != 201 && enable.statusCode != 200) {
        return DeployResult.err('Could not enable Pages: ${enable.body}');
      }
    }
    if (customDomain != null && customDomain.isNotEmpty) {
      await http.put(Uri.parse('$base/pages'),
          headers: _h, body: jsonEncode({'cname': customDomain}));
    }
    return DeployResult(success: true, message: 'pages enabled');
  }

  Future<DeployResult> fullDeploy(
    ChurchWebsite site,
    void Function(String) onProgress,
  ) async {
    final d = site.settings.deploy;

    onProgress('Verifying GitHub token…');
    final verify = await verifyToken();
    if (!verify.success) return verify;
    final username = verify.message;

    onProgress('Setting up repository…');
    final repo = await _ensureRepo(username, d.githubRepo);
    if (!repo.success) return repo;

    onProgress('Building website files…');
    final export = await exportWebsiteToMemory(site);
    if (export.error != null) return DeployResult.err('Export failed: ${export.error}');

    onProgress('Uploading ${export.files.length} files to GitHub…');
    final push = await _pushFiles(username, d.githubRepo, export.fileContents);
    if (!push.success) return push;

    onProgress('Enabling GitHub Pages…');
    final domain = d.customDomain.isNotEmpty ? d.customDomain : null;
    final pages  = await _enablePages(username, d.githubRepo, domain);
    if (!pages.success) return pages;

    final liveUrl = domain != null
        ? 'https://$domain'
        : 'https://$username.github.io/${d.githubRepo}';

    return DeployResult(
      success:     true,
      message:     '🎉 Deployed! Live in ~1 minute.',
      liveUrl:     liveUrl,
      cnameTarget: '$username.github.io',
    );
  }
}

// ─── Cloudflare Deploy Service ────────────────────────────────────────────────

class CloudflareDeployService {
  final String apiToken;
  final String accountId;
  static const _api = 'https://api.cloudflare.com/client/v4';
  CloudflareDeployService(this.apiToken, this.accountId);

  Map<String, String> get _h => {
    'Authorization': 'Bearer $apiToken',
    'Content-Type':  'application/json',
  };

  Future<DeployResult> verifyToken() async {
    try {
      final res = await http.get(
          Uri.parse('$_api/user/tokens/verify'), headers: _h);
      if (res.statusCode != 200) {
        return DeployResult.err(
          'Invalid Cloudflare token.\n'
          'Create one at dash.cloudflare.com/profile/api-tokens\n'
          'with "Cloudflare Pages: Edit" permission.');
      }
      return DeployResult(success: true, message: 'token valid');
    } catch (e) {
      return DeployResult.err('Network error: $e');
    }
  }

  Future<DeployResult> _ensureProject(String name) async {
    final check = await http.get(
        Uri.parse('$_api/accounts/$accountId/pages/projects/$name'), headers: _h);
    if (check.statusCode == 200) return DeployResult(success: true, message: 'exists');

    final create = await http.post(
      Uri.parse('$_api/accounts/$accountId/pages/projects'),
      headers: _h,
      body: jsonEncode({'name': name, 'production_branch': 'main'}),
    );
    if (create.statusCode == 200 || create.statusCode == 201) {
      return DeployResult(success: true, message: 'created');
    }
    return DeployResult.err('Could not create CF project: ${create.body}');
  }

  Future<DeployResult> _uploadFiles(
      String projectName, Map<String, String> files) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
          '$_api/accounts/$accountId/pages/projects/$projectName/deployments'),
    );
    request.headers['Authorization'] = 'Bearer $apiToken';

    for (final e in files.entries) {
      request.files.add(http.MultipartFile.fromString(
        e.key.replaceAll(RegExp(r'[/.]'), '_'),
        e.value,
        filename: e.key,
      ));
    }

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 200 || res.statusCode == 201) {
      final data = jsonDecode(res.body);
      final url  = data['result']?['url'] as String?
          ?? 'https://$projectName.pages.dev';
      return DeployResult(success: true, message: 'uploaded', liveUrl: url);
    }
    return DeployResult.err(
        'Upload failed (${res.statusCode}). Check your Account ID and token permissions.');
  }

  Future<void> _setCustomDomain(String projectName, String domain) async {
    await http.post(
      Uri.parse('$_api/accounts/$accountId/pages/projects/$projectName/domains'),
      headers: _h,
      body: jsonEncode({'name': domain}),
    );
  }

  Future<String?> fetchZoneId(String domain) async {
    final parts = domain.split('.');
    final root  = parts.length >= 2
        ? '${parts[parts.length - 2]}.${parts.last}' : domain;
    final res   = await http.get(Uri.parse('$_api/zones?name=$root'), headers: _h);
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body)['result'] as List? ?? [];
      if (list.isNotEmpty) return list.first['id'] as String?;
    }
    return null;
  }

  Future<void> upsertCname(String zoneId, String name, String target) async {
    final list = await http.get(
        Uri.parse('$_api/zones/$zoneId/dns_records?type=CNAME&name=$name'),
        headers: _h);
    final existing = (jsonDecode(list.body)['result'] as List? ?? []);
    final body = jsonEncode({
      'type': 'CNAME', 'name': name,
      'content': target, 'ttl': 1, 'proxied': true,
    });
    if (existing.isNotEmpty) {
      await http.put(
        Uri.parse('$_api/zones/$zoneId/dns_records/${existing.first['id']}'),
        headers: _h, body: body,
      );
    } else {
      await http.post(
        Uri.parse('$_api/zones/$zoneId/dns_records'),
        headers: _h, body: body,
      );
    }
  }

  Future<DeployResult> fullDeploy(
    ChurchWebsite site,
    void Function(String) onProgress,
  ) async {
    final d = site.settings.deploy;

    onProgress('Verifying Cloudflare token…');
    final verify = await verifyToken();
    if (!verify.success) return verify;

    onProgress('Setting up Cloudflare Pages project…');
    final project = await _ensureProject(d.cloudflareProject);
    if (!project.success) return project;

    onProgress('Building website files…');
    final export = await exportWebsiteToMemory(site);
    if (export.error != null) return DeployResult.err(export.error!);

    onProgress('Uploading to Cloudflare…');
    final upload = await _uploadFiles(d.cloudflareProject, export.fileContents);
    if (!upload.success) return upload;

    final pagesUrl = upload.liveUrl.isNotEmpty
        ? upload.liveUrl
        : 'https://${d.cloudflareProject}.pages.dev';
    String finalUrl = pagesUrl;

    if (d.customDomain.isNotEmpty) {
      onProgress('Attaching custom domain…');
      await _setCustomDomain(d.cloudflareProject, d.customDomain);
      finalUrl = 'https://${d.customDomain}';

      if (d.domainRegistrar == DomainRegistrar.cloudflare) {
        onProgress('Auto-configuring DNS records…');
        final zoneId = await fetchZoneId(d.customDomain);
        if (zoneId != null) {
          final target = '${d.cloudflareProject}.pages.dev';
          await upsertCname(zoneId, d.customDomain, target);
          await upsertCname(zoneId, 'www.${d.customDomain}', target);
        }
      }
    }

    return DeployResult(
      success:     true,
      message:     '🎉 Deployed to Cloudflare Pages!',
      liveUrl:     finalUrl,
      cnameTarget: '${d.cloudflareProject}.pages.dev',
    );
  }
}