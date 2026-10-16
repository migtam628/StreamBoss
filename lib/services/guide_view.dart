/// How big the player at the top of the Guide is (the "view options", like YouTube's default and theater views).
enum GuideView { compact, large, theater, off }

/// The saved name back to a view; anything unknown is the compact one the Guide always had.
GuideView parseGuideView(String? name) =>
    GuideView.values.firstWhere((v) => v.name == name, orElse: () => GuideView.compact);

/// The size of the picture for [view], in a Guide [maxWidth] wide on a screen [screenHeight] tall.
/// Large puts the picture beside the details, theater spreads it over the full width; both stay under
/// a share of the screen's height so the guide below always keeps room.
({double width, double height}) guideVideoSize(GuideView view, {required double maxWidth, required double screenHeight}) {
  switch (view) {
    case GuideView.compact:
      final w = maxWidth + 40 >= 700 ? 220.0 : 128.0;
      return (width: w, height: w * 9 / 16);
    case GuideView.large:
      var w = (maxWidth * (maxWidth + 40 >= 700 ? 0.5 : 0.55)).clamp(128.0, 560.0);
      final cap = screenHeight * 0.38;
      if (w * 9 / 16 > cap) w = cap * 16 / 9;
      return (width: w, height: w * 9 / 16);
    case GuideView.theater:
      final h = (maxWidth * 9 / 16).clamp(0.0, screenHeight * 0.42);
      return (width: maxWidth, height: h);
    case GuideView.off:
      return (width: 0, height: 0);
  }
}
