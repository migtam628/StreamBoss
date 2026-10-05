/// Where the project lives (used by "Check for updates", releases and bug reports).
const kRepoSlug = 'migtam628/StreamBoss';
const kRepoUrl = 'https://github.com/$kRepoSlug';
const kReleasesUrl = '$kRepoUrl/releases';
const kIssuesUrl = '$kRepoUrl/issues';

/// The full version, e.g. `0.3.0b2`. Release builds set it from the git tag
/// (`--dart-define=APP_VERSION=...`); the platform version fields only hold the numeric x.y.z.
/// Empty for local builds, which fall back to the version in pubspec.yaml.
const kVersionLabel = String.fromEnvironment('APP_VERSION');

/// What to show and compare: the tag's full version when known, else the platform version.
String appVersion(String platformVersion) => kVersionLabel.isNotEmpty ? kVersionLabel : platformVersion;
