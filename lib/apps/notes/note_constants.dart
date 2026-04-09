// lib/apps/notes/note_constants.dart
//
// Folder identifiers, topic lists, and Bible book lists.
// Edit topicalSubfolders to add/remove sermon topic categories.
// Edit booksOT / booksNT if you need to customise the book picker.

// ── FOLDER IDs ────────────────────────────────────────────────────────────────

const kFolderTopical      = 'Topical';
const kFolderExpositional = 'Expositional';
const kFolderTextual      = 'Textual';   // ← NEW: verse-by-verse / textual sermons
const kFolderGeneral      = 'General';
const kFolderPrayer       = 'Prayer';
const kFolderMeeting      = 'Meeting';
const kFolderArchive      = 'Archive';

// ── TOPICAL SUB-FOLDERS ───────────────────────────────────────────────────────
// Add new topics here; they appear automatically in the folder tree.

const topicalSubfolders = <String>[
  'Christmas',
  'Easter / Resurrection',
  'Good Friday',
  'Palm Sunday',
  'Pentecost',
  'Thanksgiving',
  'New Year',
  "Mother's Day",
  "Father's Day",
  'Independence Day',
  'Baptism',
  "Communion / Lord's Supper",
  'Missions',
  'Marriage & Family',
  'Evangelism',
  'Discipleship',
  'Worship',
  'Stewardship',
  'Grief & Comfort',
  'Salvation',
  'Holy Spirit',
  'Prayer & Fasting',
  'Other Topical',
];

// ── BIBLE BOOKS ───────────────────────────────────────────────────────────────

const booksOT = <String>[
  'Genesis','Exodus','Leviticus','Numbers','Deuteronomy','Joshua','Judges',
  'Ruth','1 Samuel','2 Samuel','1 Kings','2 Kings','1 Chronicles','2 Chronicles',
  'Ezra','Nehemiah','Esther','Job','Psalms','Proverbs','Ecclesiastes',
  'Song of Solomon','Isaiah','Jeremiah','Lamentations','Ezekiel','Daniel',
  'Hosea','Joel','Amos','Obadiah','Jonah','Micah','Nahum','Habakkuk',
  'Zephaniah','Haggai','Zechariah','Malachi',
];

const booksNT = <String>[
  'Matthew','Mark','Luke','John','Acts','Romans','1 Corinthians','2 Corinthians',
  'Galatians','Ephesians','Philippians','Colossians','1 Thessalonians',
  '2 Thessalonians','1 Timothy','2 Timothy','Titus','Philemon','Hebrews',
  'James','1 Peter','2 Peter','1 John','2 John','3 John','Jude','Revelation',
];

// ── TEXTUAL TESTAMENT KEYS ────────────────────────────────────────────────────
// Used as the subfolder prefix for Textual notes so the tree can split them
// into OT / NT sections.  A note's subfolder is stored as "OT:Genesis" or
// "NT:Romans" so we can reconstruct both the testament group and the book.

const kTextualOT = 'OT';
const kTextualNT = 'NT';

/// Encode a testament key + book name into the subfolder string.
String textualSubfolder(String testament, String book) => '$testament:$book';

/// Decode a textual subfolder into its [testament, book] parts.
/// Returns ['', ''] if the value is not in the expected format.
List<String> parseTextualSubfolder(String subfolder) {
  final idx = subfolder.indexOf(':');
  if (idx < 1) return ['', subfolder];
  return [subfolder.substring(0, idx), subfolder.substring(idx + 1)];
}