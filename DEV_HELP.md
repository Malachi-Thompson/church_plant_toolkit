

Overview
master          ← Stable releases only. What users download.
└── prerelease      ← Testing & staging before a release goes live
    └── main_app        ← Core app logic & navigation
    └── church_profile  ← Master Church Profile (shared by all apps)
    └── app/*           ← Individual built-in tools (see below)
Code flows in one direction:
app/* or church_profile or main_app → prerelease → master

Core Branches
BranchPurposeproductionStable, released versions of the toolkit. This is what users download. Nothing merges here without passing through prerelease first.prereleaseStaging area. Features are tested and combined here before a release is cut to master.main_appThe core logic of the app — navigation, app shell, routing, and anything that ties the tools together.church_profileThe Master Church Profile. Stores church name, logo, colors, contact info, and branding. All app/* branches read from this — it is the foundation everything else builds on.

App Branches — Built-In Tools
Each app/ branch is a self-contained tool inside the toolkit. They are developed independently and merged into prerelease when ready.
BranchToolapp/bulletinBulletin Builder — Design and print weekly church bulletins. Church info auto-fills from the Church Profile.app/newsletterNewsletter Maker — Create branded email newsletters and announcements.app/presentationPresentation & Streaming — Sunday morning slides, song lyrics, sermon notes, and streaming/recording support.app/media_toolkitMedia Toolkit — Graphics, assets, and media management for the church.app/notesNotes — Sermon notes, planning documents, and pastoral resources.app/directoryDirectory — Church member directory and contact management.app/websiteWebsite — The public-facing GitHub Pages landing site for the project.servicesServices — Background services, shared utilities, and integrations used across multiple apps.

How to Work on a Branch
Switching to a branch
bashgit checkout app/bulletin
# or
git switch app/bulletin
Starting work on an app
bash# 1. Switch to the app branch
git checkout app/newsletter

# 2. Make your changes and commit
git add .
git commit -m "feat: add template picker to newsletter maker"

# 3. Push to GitHub
git push origin app/newsletter

# 4. Open a Pull Request into prerelease when ready
Release flow
bash# When prerelease is stable and tested:
# Open a Pull Request from prerelease → master

Pull Request Rules
FromIntoWhenapp/*prereleaseFeature is complete and tested locallychurch_profileprereleaseProfile changes are stablemain_appprereleaseCore logic changes are readyprereleasemasterA full release has been tested and is ready for users

Never merge directly into master. All changes must pass through prerelease first.


Check Status Errors
If you see ✗ 2/4 on a branch in GitHub, it means a GitHub Actions check is failing. This is expected on branches that haven't been fully set up yet and won't affect your local development. These will clear up as the CI/CD workflow is configured.

For questions or to suggest a new app branch, open a feature request.