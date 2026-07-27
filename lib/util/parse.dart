// Media parse helpers normalize media references from user and channel input.
// Dart port of parse.ts

import 'dart:io';

/// Captures legacy MEDIA: attachment directives from model/tool output.
final RegExp mediaTokenRe = RegExp(r'\bMEDIA:\s*`?([^\n]+)`?', caseSensitive: false);

/// Ordered output segment emitted after visible text and extracted media are separated.
sealed class ParsedMediaOutputSegment {}

class TextSegment extends ParsedMediaOutputSegment {
  String text;
  TextSegment(this.text);

  @override
  String toString() => 'TextSegment(text: $text)';
}

class MediaSegment extends ParsedMediaOutputSegment {
  final String url;
  MediaSegment(this.url);

  @override
  String toString() => 'MediaSegment(url: $url)';
}

/// Controls which non-MEDIA syntaxes may be lifted into media attachments.
class SplitMediaFromOutputOptions {
  final bool extractMarkdownImages;
  final bool extractMediaDirectives;

  const SplitMediaFromOutputOptions({
    this.extractMarkdownImages = false,
    this.extractMediaDirectives = true,
  });
}

/// Converts file URLs into plain local paths before downstream media validation.
String normalizeMediaSource(String src) {
  return src.startsWith('file://') ? src.replaceFirst('file://', '') : src;
}

final RegExp _trailingSerializedJsonAfterExtRe =
    RegExp(r'^(.*\.\w{1,10})\\?"(?=[\]},:,]|$).*', dotAll: true);

String _cleanCandidate(String raw) {
  String stripped = raw;
  // replace /^[`"'[{(]+/
  stripped = stripped.replaceFirst(RegExp(r"""^[`"'\[{(]+"""), '');
  // replace /[`"'\\})\],]+$/
  stripped = stripped.replaceFirst(RegExp(r"""[`"'\\})\],]+$"""), '');
  final jsonSuffixMatch = _trailingSerializedJsonAfterExtRe.firstMatch(stripped);
  return jsonSuffixMatch?.group(1) ?? stripped;
}

final RegExp _windowsDriveRe = RegExp(r'^[a-zA-Z]:[\\/]');
final RegExp _schemeRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:');
final RegExp _hasFileExt = RegExp(r'\.\w{1,10}$');

// Matches ".." as a standalone path segment (start, middle, or end).
final RegExp _traversalSegmentRe = RegExp(r'(?:^|[/\\])\.\.(?:[/\\]|$)');

bool _isSupportedHomeRelativePath(String candidate) {
  return candidate.startsWith('~/') || candidate.startsWith(r'~\');
}

bool _hasTraversalOrUnsupportedHomeDirPrefix(String candidate) {
  return candidate.startsWith('../') ||
      candidate == '..' ||
      (candidate.startsWith('~') && !_isSupportedHomeRelativePath(candidate)) ||
      _traversalSegmentRe.hasMatch(candidate);
}

// Broad structural check: does this look like a local file path? Used only for
// stripping MEDIA: lines from output text — never for media approval.
bool _looksLikeLocalFilePath(String candidate) {
  return candidate.startsWith('/') ||
      candidate.startsWith('./') ||
      candidate.startsWith('../') ||
      candidate.startsWith('~') ||
      _windowsDriveRe.hasMatch(candidate) ||
      candidate.startsWith(r'\\') ||
      (!_schemeRe.hasMatch(candidate) &&
          (candidate.contains('/') || candidate.contains(r'\')));
}

// Recognize safe local file path patterns for media approval, rejecting
// traversal and unsupported home-dir paths so they never reach downstream load/send logic.
bool _isLikelyLocalPath(String candidate) {
  if (_hasTraversalOrUnsupportedHomeDirPrefix(candidate)) {
    return false;
  }
  return candidate.startsWith('/') ||
      candidate.startsWith('./') ||
      _isSupportedHomeRelativePath(candidate) ||
      _windowsDriveRe.hasMatch(candidate) ||
      candidate.startsWith(r'\\') ||
      (!_schemeRe.hasMatch(candidate) &&
          (candidate.contains('/') || candidate.contains(r'\')));
}

String _normalizeRemoteMediaHostname(String value) {
  String normalized = value.trim().toLowerCase();
  // replace /^\[|\]$/g with ''
  normalized = normalized.replaceAll(RegExp(r'^\[|\]$'), '');
  // replace /\.+$/ with ''
  normalized = normalized.replaceAll(RegExp(r'\.+$'), '');
  if (normalized.split('.').any((label) => label.isEmpty)) {
    return '';
  }
  return normalized;
}

bool _isBlockedRemoteMediaHostname(String hostname) {
  final normalized = _normalizeRemoteMediaHostname(hostname);
  if (normalized.isEmpty) return true;
  if (!normalized.contains('.')) return true;
  if (normalized == 'localhost' ||
      normalized == 'localhost.localdomain' ||
      normalized == 'metadata.google.internal' ||
      normalized.endsWith('.localhost') ||
      normalized.endsWith('.local') ||
      normalized.endsWith('.internal')) {
    return true;
  }

  // Dart equivalent of parseCanonicalIpAddress / isBlockedSpecialUseIpv4Address
  final addr = InternetAddress.tryParse(normalized);
  if (addr != null) {
    if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) return true;
    if (addr.type == InternetAddressType.IPv4) {
      final b = addr.rawAddress;
      if (b[0] == 10) return true;
      if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
      if (b[0] == 192 && b[1] == 168) return true;
      if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true; // CGNAT
      if (b[0] == 169 && b[1] == 254) return true; // Link-local
      if (b[0] == 127) return true;
      if (b[0] == 0) return true; // 0.x.x.x
      if (b[0] == 240) return true; // 240.x.x.x reserved
      if (b[0] == 255 && b[1] == 255 && b[2] == 255 && b[3] == 255) return true; // broadcast
    }
    // IPv6 special use
    if (addr.type == InternetAddressType.IPv6) {
      final b = addr.rawAddress;
      // ::1 loopback handled by isLoopback
      // fc00::/7 unique local
      if ((b[0] & 0xfe) == 0xfc) return true;
      // fe80::/10 link-local handled by isLinkLocal
    }
    return false;
  }

  // Block if contains ":" but is not a valid IP (malformed IPv6)
  if (normalized.contains(':')) return true;

  return false;
}

bool _isAllowedRemoteMediaUrl(String candidate) {
  try {
    final parsed = Uri.parse(candidate);
    return parsed.scheme == 'https' &&
        parsed.userInfo.isEmpty &&
        !_isBlockedRemoteMediaHostname(parsed.host);
  } catch (_) {
    return false;
  }
}

bool _isValidMedia(
  String candidate, {
  bool allowSpaces = false,
  bool allowBareFilename = false,
}) {
  if (candidate.isEmpty) return false;
  if (candidate.length > 4096) return false;
  if (!allowSpaces && RegExp(r'\s').hasMatch(candidate)) return false;
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(candidate)) {
    return _isAllowedRemoteMediaUrl(candidate);
  }
  if (_isLikelyLocalPath(candidate)) return true;
  // Hard reject traversal/unsupported home-dir patterns before the bare-filename fallback
  if (_hasTraversalOrUnsupportedHomeDirPrefix(candidate)) return false;
  // Accept bare filenames only when the caller opts in.
  if (allowBareFilename &&
      !_schemeRe.hasMatch(candidate) &&
      _hasFileExt.hasMatch(candidate)) {
    return true;
  }
  return false;
}

String? _unwrapQuoted(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 2) return null;
  final first = trimmed[0];
  final last = trimmed[trimmed.length - 1];
  if (first != last) return null;
  if (first != '"' && first != "'" && first != '`') return null;
  return trimmed.substring(1, trimmed.length - 1).trim();
}

bool _mayContainFenceMarkers(String input) {
  return input.contains('```') || input.contains('~~~');
}

String _cleanLineText(String text) {
  return text.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
}

class _MarkdownImageMatch {
  final int start;
  final int end;
  final String destination;

  _MarkdownImageMatch({
    required this.start,
    required this.end,
    required this.destination,
  });
}

const int _maxMarkdownImageLineLength = 20000;
const int _maxMarkdownImageAttemptsPerLine = 80;
const int _maxMarkdownImageMatchesPerLine = 50;

int? _findMatchingBracket(String input, int start, String open, String close) {
  int depth = 1;
  for (int i = start; i < input.length; i += 1) {
    final ch = input[i];
    if (ch == '\\') {
      i += 1;
      continue;
    }
    if (ch == open) {
      depth += 1;
      continue;
    }
    if (ch != close) continue;
    depth -= 1;
    if (depth == 0) return i;
  }
  return null;
}

bool _isRemoteMarkdownImageMedia(String candidate) {
  return RegExp(r'^https?://', caseSensitive: false).hasMatch(candidate) &&
      _isValidMedia(candidate);
}

int? _parseMarkdownTitle(String input, int start) {
  int index = start;
  while (index < input.length && RegExp(r'\s').hasMatch(input[index])) {
    index += 1;
  }
  if (index >= input.length) return null;
  final opener = input[index];
  final String? closer = (opener == '"' || opener == "'")
      ? opener
      : (opener == '(' ? ')' : null);
  if (closer == null) return null;

  int? closingIndex;
  if (opener == '(') {
    closingIndex = _findMatchingBracket(input, index + 1, '(', ')');
  } else {
    for (int i = index + 1; i < input.length; i += 1) {
      final ch = input[i];
      if (ch == '\\') {
        i += 1;
        continue;
      }
      if (ch == closer) {
        closingIndex = i;
        break;
      }
    }
  }

  if (closingIndex == null) return null;
  int tailIndex = closingIndex + 1;
  while (tailIndex < input.length && RegExp(r'\s').hasMatch(input[tailIndex])) {
    tailIndex += 1;
  }
  return (tailIndex < input.length && input[tailIndex] == ')') ? tailIndex + 1 : null;
}

({String destination, int end})? _parseMarkdownImageDestination(String input, int start) {
  int index = start;
  while (index < input.length && RegExp(r'\s').hasMatch(input[index])) {
    index += 1;
  }
  if (index >= input.length) return null;

  if (input[index] == '<') {
    int closing = index + 1;
    while (closing < input.length) {
      final ch = input[closing];
      if (ch == '\\') {
        closing += 2;
        continue;
      }
      if (ch == '>') {
        final destination = input.substring(index + 1, closing).trim();
        if (destination.isEmpty) return null;
        int tailIndex = closing + 1;
        while (
            tailIndex < input.length && RegExp(r'\s').hasMatch(input[tailIndex])) {
          tailIndex += 1;
        }
        if (tailIndex < input.length && input[tailIndex] == ')') {
          return (destination: destination, end: tailIndex + 1);
        }
        final titledEnd = _parseMarkdownTitle(input, tailIndex);
        return titledEnd != null ? (destination: destination, end: titledEnd) : null;
      }
      closing += 1;
    }
    return null;
  }

  final destinationStart = index;
  int destinationEnd = index;
  int parenDepth = 0;
  while (index < input.length) {
    final ch = input[index];
    if (ch == '\\') {
      index += 2;
      destinationEnd = index;
      continue;
    }
    if (ch == '(') {
      parenDepth += 1;
      index += 1;
      destinationEnd = index;
      continue;
    }
    if (ch == ')') {
      if (parenDepth == 0) {
        final destination = input.substring(destinationStart, destinationEnd).trim();
        return destination.isNotEmpty ? (destination: destination, end: index + 1) : null;
      }
      parenDepth -= 1;
      index += 1;
      destinationEnd = index;
      continue;
    }
    if (RegExp(r'\s').hasMatch(ch) && parenDepth == 0) {
      final destination = input.substring(destinationStart, destinationEnd).trim();
      if (destination.isEmpty) return null;
      final titledEnd = _parseMarkdownTitle(input, index);
      return titledEnd != null ? (destination: destination, end: titledEnd) : null;
    }
    index += 1;
    destinationEnd = index;
  }
  return null;
}

List<_MarkdownImageMatch> _findMarkdownImageMatches(String line) {
  if (line.length > _maxMarkdownImageLineLength) return [];
  final matches = <_MarkdownImageMatch>[];
  int searchIndex = 0;
  int attempts = 0;
  while (matches.length < _maxMarkdownImageMatchesPerLine &&
      attempts < _maxMarkdownImageAttemptsPerLine) {
    final index = line.indexOf('![', searchIndex);
    if (index < 0) break;
    attempts += 1;
    final altEnd = _findMatchingBracket(line, index + 2, '[', ']');
    if (altEnd == null || (altEnd + 1 >= line.length) || line[altEnd + 1] != '(') {
      searchIndex = index + 2;
      continue;
    }
    final parsed = _parseMarkdownImageDestination(line, altEnd + 2);
    if (parsed == null) {
      searchIndex = index + 2;
      continue;
    }
    matches.add(_MarkdownImageMatch(
      start: index,
      end: parsed.end,
      destination: parsed.destination,
    ));
    searchIndex = parsed.end;
  }
  return matches;
}

({String? cleanedLine, List<ParsedMediaOutputSegment> lineSegments, bool foundMedia})
    _collectMarkdownImageSegments({required String line, required List<String> media}) {
  final matches = _findMarkdownImageMatches(line);
  if (matches.isEmpty) {
    return (lineSegments: [], foundMedia: false, cleanedLine: null);
  }

  final segmentPieces = <String>[];
  final visiblePieces = <String>[];
  final lineSegments = <ParsedMediaOutputSegment>[];
  int cursor = 0;
  bool foundMedia = false;

  for (final match in matches) {
    final before = line.substring(cursor, match.start);
    segmentPieces.add(before);
    visiblePieces.add(before);

    final target = normalizeMediaSource(
      _cleanCandidate(_unwrapQuoted(match.destination) ?? match.destination),
    );
    if (_isRemoteMarkdownImageMedia(target)) {
      final beforeText = _cleanLineText(segmentPieces.join(''));
      if (beforeText.isNotEmpty) {
        lineSegments.add(TextSegment(beforeText));
      }
      segmentPieces.clear();
      media.add(target);
      lineSegments.add(MediaSegment(target));
      foundMedia = true;
    } else {
      final original = line.substring(match.start, match.end);
      segmentPieces.add(original);
      visiblePieces.add(original);
    }

    cursor = match.end;
  }

  final after = line.substring(cursor);
  segmentPieces.add(after);
  visiblePieces.add(after);
  final trailingText = _cleanLineText(segmentPieces.join(''));
  if (trailingText.isNotEmpty) {
    lineSegments.add(TextSegment(trailingText));
  }
  final cleanedLine = _cleanLineText(visiblePieces.join(''));

  return (
    cleanedLine: cleanedLine.isNotEmpty ? cleanedLine : null,
    lineSegments: lineSegments,
    foundMedia: foundMedia,
  );
}

// Check if a character offset is inside any fenced code block
bool _isInsideFence(List<({int start, int end})> fenceSpans, int offset) {
  return fenceSpans.any((span) => offset >= span.start && offset < span.end);
}

/// Simple fence span parser: finds ``` or ~~~ fenced code blocks.
/// Returns a list of {start, end} character ranges (inclusive start, exclusive end).
List<({int start, int end})> _parseFenceSpans(String text) {
  final spans = <({int start, int end})>[];
  final lines = text.split('\n');
  int offset = 0;
  String? openFence;
  int fenceStart = 0;

  for (final line in lines) {
    final trimmed = line.trimLeft();
    final isBacktickFence = trimmed.startsWith('```');
    final isTildeFence = trimmed.startsWith('~~~');
    if (isBacktickFence || isTildeFence) {
      final marker = isBacktickFence ? '```' : '~~~';
      if (openFence == null) {
        openFence = marker;
        fenceStart = offset;
      } else if (openFence == marker) {
        spans.add((start: fenceStart, end: offset + line.length + 1));
        openFence = null;
      }
    }
    offset += line.length + 1; // +1 for newline
  }
  // Unclosed fence spans to end of text
  if (openFence != null) {
    spans.add((start: fenceStart, end: text.length));
  }
  return spans;
}

/// Result type for splitMediaFromOutput
class SplitMediaResult {
  final String text;
  final List<String>? mediaUrls;
  /// @deprecated Use mediaUrls[0].
  final String? mediaUrl;
  final bool? audioAsVoice;
  final List<ParsedMediaOutputSegment>? segments;

  const SplitMediaResult({
    required this.text,
    this.mediaUrls,
    this.mediaUrl,
    this.audioAsVoice,
    this.segments,
  });
}

/// Splits tool/stdout text into visible text, media attachments, voice tags, and ordered segments.
SplitMediaResult splitMediaFromOutput(
  String raw, [
  SplitMediaFromOutputOptions options = const SplitMediaFromOutputOptions(),
]) {
  // KNOWN: Leading whitespace is semantically meaningful in Markdown (lists, indented fences).
  // We only trim the end; token cleanup below handles removing `MEDIA:` lines.
  final trimmedRaw = raw.trimRight();
  if (trimmedRaw.trim().isEmpty) {
    return const SplitMediaResult(text: '');
  }
  final extractMarkdownImages = options.extractMarkdownImages == true;
  final extractMediaDirectives = options.extractMediaDirectives != false;
  final mayContainMediaToken =
      extractMediaDirectives && RegExp(r'media:', caseSensitive: false).hasMatch(trimmedRaw);
  final mayContainMarkdownImage =
      extractMarkdownImages && RegExp(r'!\[[^\]]*]\(').hasMatch(trimmedRaw);
  final mayContainAudioTag = trimmedRaw.contains('[[');
  if (!mayContainMediaToken && !mayContainMarkdownImage && !mayContainAudioTag) {
    return SplitMediaResult(text: trimmedRaw);
  }

  final media = <String>[];
  bool foundMediaToken = false;
  final segments = <ParsedMediaOutputSegment>[];

  void pushTextSegment(String text) {
    if (text.isEmpty) return;
    final last = segments.isNotEmpty ? segments.last : null;
    if (last is TextSegment) {
      last.text = '${last.text}\n$text';
      return;
    }
    segments.add(TextSegment(text));
  }

  // Parse fenced code blocks to avoid extracting MEDIA tokens from inside them
  final hasFenceMarkers = _mayContainFenceMarkers(trimmedRaw);
  final fenceSpans = hasFenceMarkers ? _parseFenceSpans(trimmedRaw) : <({int start, int end})>[];

  // Line-wise parsing preserves visible text while letting MEDIA-only lines disappear cleanly.
  final lines = trimmedRaw.split('\n');
  final keptLines = <String>[];

  int lineOffset = 0; // Track character offset for fence checking
  for (final line in lines) {
    // Fenced examples must remain text; extracting their MEDIA tokens would mutate transcripts.
    if (hasFenceMarkers && _isInsideFence(fenceSpans, lineOffset)) {
      keptLines.add(line);
      pushTextSegment(line);
      lineOffset += line.length + 1; // +1 for newline
      continue;
    }

    final trimmedStart = line.trimLeft();
    if (!extractMediaDirectives || !trimmedStart.toUpperCase().startsWith('MEDIA:')) {
      final markdownImageResult = extractMarkdownImages
          ? _collectMarkdownImageSegments(line: line, media: media)
          : (lineSegments: <ParsedMediaOutputSegment>[], foundMedia: false, cleanedLine: null);
      if (!markdownImageResult.foundMedia) {
        keptLines.add(line);
        pushTextSegment(line);
      } else {
        foundMediaToken = true;
        if (markdownImageResult.cleanedLine != null) {
          keptLines.add(markdownImageResult.cleanedLine!);
        }
        for (final segment in markdownImageResult.lineSegments) {
          if (segment is TextSegment) {
            pushTextSegment(segment.text);
            continue;
          }
          segments.add(segment);
        }
      }
      lineOffset += line.length + 1; // +1 for newline
      continue;
    }

    final matchList = mediaTokenRe.allMatches(line).toList();
    if (matchList.isEmpty) {
      keptLines.add(line);
      pushTextSegment(line);
      lineOffset += line.length + 1; // +1 for newline
      continue;
    }

    final pieces = <String>[];
    final lineSegments = <ParsedMediaOutputSegment>[];
    int cursor = 0;

    for (final match in matchList) {
      final start = match.start;
      pieces.add(line.substring(cursor, start));

      final payload = match.group(1)!;
      final unwrapped = _unwrapQuoted(payload);
      final payloadValue = unwrapped ?? payload;
      final parts = unwrapped != null
          ? [unwrapped]
          : payload.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      final mediaStartIndex = media.length;
      int validCount = 0;
      final invalidParts = <String>[];
      bool hasValidMedia = false;
      for (final part in parts) {
        final candidate = normalizeMediaSource(_cleanCandidate(part));
        if (_isValidMedia(candidate, allowSpaces: unwrapped != null)) {
          media.add(candidate);
          hasValidMedia = true;
          foundMediaToken = true;
          validCount += 1;
        } else {
          invalidParts.add(part);
        }
      }

      final trimmedPayload = payloadValue.trim();
      final looksLikeLocalPath =
          _looksLikeLocalFilePath(trimmedPayload) || trimmedPayload.startsWith('file://');
      if (unwrapped == null &&
          validCount == 1 &&
          invalidParts.isNotEmpty &&
          RegExp(r'\s').hasMatch(payloadValue) &&
          looksLikeLocalPath) {
        // A single valid split plus invalid leftovers can be one local path containing spaces.
        final fallback = normalizeMediaSource(_cleanCandidate(payloadValue));
        if (_isValidMedia(fallback, allowSpaces: true)) {
          media.replaceRange(mediaStartIndex, media.length, [fallback]);
          hasValidMedia = true;
          foundMediaToken = true;
          validCount = 1;
          invalidParts.clear();
        }
      }

      if (!hasValidMedia && unwrapped == null && RegExp(r'\s').hasMatch(payloadValue)) {
        final spacedFallback = normalizeMediaSource(_cleanCandidate(payloadValue));
        if (_isValidMedia(spacedFallback, allowSpaces: true, allowBareFilename: true)) {
          media.replaceRange(mediaStartIndex, media.length, [spacedFallback]);
          hasValidMedia = true;
          foundMediaToken = true;
          validCount = 1;
          invalidParts.clear();
        }
      }

      if (!hasValidMedia) {
        final fallback = normalizeMediaSource(_cleanCandidate(payloadValue));
        if (_isValidMedia(fallback, allowSpaces: true, allowBareFilename: true)) {
          media.add(fallback);
          hasValidMedia = true;
          foundMediaToken = true;
          invalidParts.clear();
        }
      }

      if (hasValidMedia) {
        final beforeText = _cleanLineText(pieces.join(''));
        if (beforeText.isNotEmpty) {
          lineSegments.add(TextSegment(beforeText));
        }
        pieces.clear();
        for (final url
            in media.sublist(mediaStartIndex, mediaStartIndex + validCount)) {
          lineSegments.add(MediaSegment(url));
        }
        if (invalidParts.isNotEmpty) {
          pieces.add(invalidParts.join(' '));
        }
      } else if (looksLikeLocalPath) {
        // Strip MEDIA: lines with local paths even when invalid.
        foundMediaToken = true;
      } else {
        // If no valid media was found in this match, keep the original token text.
        pieces.add(match.group(0)!);
      }

      cursor = start + match.group(0)!.length;
    }

    pieces.add(line.substring(cursor));

    final cleanedLine = _cleanLineText(pieces.join(''));

    // If the line becomes empty, drop it.
    if (cleanedLine.isNotEmpty) {
      keptLines.add(cleanedLine);
      lineSegments.add(TextSegment(cleanedLine));
    }
    for (final segment in lineSegments) {
      if (segment is TextSegment) {
        pushTextSegment(segment.text);
        continue;
      }
      segments.add(segment);
    }
    lineOffset += line.length + 1; // +1 for newline
  }

  String cleanedText = keptLines
      .join('\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();

  // Detect and strip [[audio_as_voice]] tag
  final audioTagResult = _parseAudioTag(cleanedText);
  final hasAudioAsVoice = audioTagResult.audioAsVoice;
  if (audioTagResult.hadTag) {
    cleanedText = audioTagResult.text.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
  }

  if (media.isEmpty) {
    final parsedText = (foundMediaToken || hasAudioAsVoice) ? cleanedText : trimmedRaw;
    return SplitMediaResult(
      text: parsedText,
      segments: parsedText.isNotEmpty ? [TextSegment(parsedText)] : [],
      audioAsVoice: hasAudioAsVoice ? true : null,
    );
  }

  return SplitMediaResult(
    text: cleanedText,
    mediaUrls: media,
    mediaUrl: media.isNotEmpty ? media[0] : null,
    segments: segments.isNotEmpty ? segments : [TextSegment(cleanedText)],
    audioAsVoice: hasAudioAsVoice ? true : null,
  );
}

/// Simple [[audio_as_voice]] tag parser (Dart equivalent of parseAudioTag).
({String text, bool hadTag, bool audioAsVoice}) _parseAudioTag(String input) {
  const tag = '[[audio_as_voice]]';
  final lower = input.toLowerCase();
  if (!lower.contains(tag)) {
    return (text: input, hadTag: false, audioAsVoice: false);
  }
  final cleaned = input.replaceAll(RegExp(r'\[\[audio_as_voice\]\]', caseSensitive: false), '').trim();
  return (text: cleaned, hadTag: true, audioAsVoice: true);
}
