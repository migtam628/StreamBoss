/// Where the project's website and downloads live. The code is private; the builds are published on the website,
/// with `releases.json` listing them (the same shape GitHub's releases list has, newest first).
const kSiteUrl = 'https://streamboss.site';
const kReleasesFeed = '$kSiteUrl/releases.json';
const kReleasesUrl = '$kSiteUrl/downloads/';

/// Where "Report a problem" goes.
const kSupportUrl = kSiteUrl;

/// The full version, e.g. `0.3.0b2`. Release builds set it from the git tag
/// (`--dart-define=APP_VERSION=...`); the platform version fields only hold the numeric x.y.z.
/// Empty for local builds, which fall back to the version in pubspec.yaml.
const kVersionLabel = String.fromEnvironment('APP_VERSION');

/// What to show and compare: the tag's full version when known, else the platform version.
String appVersion(String platformVersion) => kVersionLabel.isNotEmpty ? kVersionLabel : platformVersion;
