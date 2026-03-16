// RECORDING SQL
//
// Schema:
//   id                   - UUID (v4) uniquely identifying this recording
//   recording_location   - absolute file path to the video file on device
//   recording_length     - duration of the recording in seconds
//   recording_size       - size of the recording file in MB (nullable until written)
//   thumbnail_location   - absolute file path to the thumbnail image on device (nullable)
//
// Only one recording row ever exists. It is upserted on each app launch
// and reused across sessions. Only gets deleted when the user wants it to be.
// It can grow/shrink in size as settings constraints change.

const createRecordingTable = '''
  CREATE TABLE IF NOT EXISTS recording (
    id TEXT PRIMARY KEY,
    recording_location TEXT NOT NULL,
    recording_length INTEGER NOT NULL,
    recording_size INTEGER,
    thumbnail_location TEXT
  )
''';

const insertRecording = '''
  INSERT OR REPLACE INTO recording (id, recording_location, recording_length, recording_size, thumbnail_location)
  VALUES (?, ?, ?, ?, ?)
''';

const selectRecording = '''
  SELECT id, recording_location, recording_length, recording_size, thumbnail_location
  FROM recording
  LIMIT 1
''';

const updateRecording = '''
  UPDATE recording
  SET recording_location   = ?,
      recording_length     = ?,
      recording_size       = ?,
      thumbnail_location   = ?
  WHERE id = ?
''';

const deleteRecording = '''
  DELETE FROM recording
  WHERE id = ?
''';

// ==================================================================================================
// ==================================================================================================
// ==================================================================================================

// CLIPS SQL
//
// Schema:
//   id                 - UUID (v4) uniquely identifying this clip
//   date_time          - ISO 8601 timestamp of when the clip was created
//   date_time_pretty   - human-readable version of date_time
//   clip_length        - duration of the clip in seconds
//   clip_size          - size of the clip file in MB
//   trigger_type       - what caused the clip to be saved (e.g. manual, impact)
//   is_flagged         - 0 = normal, 1 = marked for deletion by the app
//   clip_location      - absolute file path to the clip video file on device
//   thumbnail_location - absolute file path to the clip thumbnail image on device

const createClipsTable = '''
  CREATE TABLE IF NOT EXISTS clips (
    id TEXT PRIMARY KEY,
    date_time TEXT NOT NULL,
    date_time_pretty TEXT NOT NULL,
    clip_length INTEGER NOT NULL,
    clip_size INTEGER NOT NULL,
    trigger_type TEXT NOT NULL,
    is_flagged INTEGER NOT NULL DEFAULT 0,
    clip_location TEXT NOT NULL,
    thumbnail_location TEXT NOT NULL
  )
''';

const insertClip = '''
  INSERT INTO clips (id, date_time, date_time_pretty, clip_length, clip_size, trigger_type, is_flagged, clip_location, thumbnail_location)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
''';

const selectAllClips = '''
  SELECT id, date_time, date_time_pretty, clip_length, clip_size, trigger_type, is_flagged, clip_location, thumbnail_location
  FROM clips
  ORDER BY date_time DESC
''';

const updateClipFlag = '''
  UPDATE clips
  SET is_flagged = ?
  WHERE id = ?
''';

const deleteClip = '''
  DELETE FROM clips
  WHERE id = ?
''';

// should only be used by the app
const deleteOldestClip = '''
  DELETE FROM clips
  WHERE id = (
    SELECT id FROM clips
    ORDER BY date_time ASC
    LIMIT 1
  )
''';