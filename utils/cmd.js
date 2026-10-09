.pragma library

// Shared argv builders for destructive file ops. Always arrays, path after "--".

function removeFileArgs(path) {
  return ["rm", "-f", "--", path];
}
