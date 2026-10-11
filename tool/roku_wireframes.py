"""Draws the wireframes in docs/roku/wireframes/ from the real layout of the Roku channel.

The sizes and positions come from roku/components/MainScene.xml and the screens from MainScene.brs, so
when either changes, update the numbers here and run:

    python3 tool/roku_wireframes.py docs/roku/wireframes

Plain Python 3, no packages. Each screen becomes one SVG file.
"""
import html, os, sys
OUT = sys.argv[1]
BG, SURF, ACC, MUT, TXT, LINE = '#0B0B12', '#161622', '#FF3D71', '#8C8CA1', '#F2F2F7', '#2B2B3D'
def esc(s): return html.escape(s, quote=True)

class S:
    def __init__(s, w=1280, h=720, note=None):
        s.w, s.h, s.p = w, h, []
    def add(s, x): s.p.append(x)
    def rect(s, x, y, w, h, fill='none', stroke=None, sw=1, rx=0, dash=None, op=None):
        a = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"'
        if stroke: a += f' stroke="{stroke}" stroke-width="{sw}"'
        if dash: a += f' stroke-dasharray="{dash}"'
        if op is not None: a += f' fill-opacity="{op}"'
        s.add(a + '/>')
    def text(s, x, y, t, size=22, fill=TXT, weight=400, anchor='start', style=''):
        s.add(f'<text xml:space="preserve" x="{x}" y="{y}" font-size="{size}" fill="{fill}" font-weight="{weight}" text-anchor="{anchor}" {style}>{esc(t)}</text>')
    def line(s, x1, y1, x2, y2, stroke=MUT, sw=1, dash=None, arrow=False):
        a = f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" stroke-width="{sw}"'
        if dash: a += f' stroke-dasharray="{dash}"'
        if arrow: a += ' marker-end="url(#ah)"'
        s.add(a + '/>')
    def path(s, pts, stroke=MUT, sw=2, dash=None, arrow=True, back=False):
        d = 'M' + ' L'.join(f'{x},{y}' for x, y in pts)
        a = f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="{sw}"'
        if dash: a += f' stroke-dasharray="{dash}"'
        if arrow: a += ' marker-end="url(#ah)"'
        if back: a += ' marker-start="url(#ah)"'
        s.add(a + '/>')
    def svg(s):
        defs = f'<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{MUT}"/></marker></defs>'
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s.w} {s.h}" width="{s.w}" height="{s.h}" '
                f'font-family="Helvetica, Arial, sans-serif">{defs}<rect width="{s.w}" height="{s.h}" fill="{BG}"/>' + ''.join(s.p) + '</svg>')

def chrome(s, status='', hint=True, hint_text='OK select   *  add to My List   Left/Right switch columns'):
    s.text(40, 48, 'STREAMBOSS', 28, ACC, 700)
    s.text(290, 50, status, 20, MUT)
    if hint: s.text(40, 696, hint_text, 20, MUT)

TABS = ['Live', 'Movies', 'Series', 'My List', 'Search', 'Settings']
def tabs(s, sel=0, focus=False):
    for i, t in enumerate(TABS):
        y = 80 + i * 46
        if i == sel:
            s.rect(30, y, 210, 46, ACC if focus else SURF, ACC, 2, 4, op=0.9 if focus else 1)
            s.text(48, y + 31, t, 22, '#fff' if focus else TXT, 700)
        else:
            s.text(48, y + 31, t, 22, MUT)

def col(s, x, w, rows, sel=None, focus=False, start_y=80, rh=40, star=()):
    for i, r in enumerate(rows):
        y = start_y + i * rh
        if sel is not None and i == sel:
            s.rect(x, y, w, rh, ACC if focus else SURF, ACC, 2, 4, op=0.9 if focus else 1)
            s.text(x + 14, y + 27, r, 21, '#fff' if focus else TXT, 700)
        else:
            s.text(x + 14, y + 27, r, 21, MUT if i not in star else ACC)

def setup_screen(kind):
    s = S()
    s.text(340, 128, 'Connect your provider', 30, TXT, 700)
    rows = ['Source type: ' + ('Xtream' if kind == 'xtream' else 'M3U playlist')]
    if kind == 'xtream':
        rows += ['Server URL: http://provider.example:8080', 'Username: demo', 'Password: ********']
    else:
        rows += ['Playlist URL: http://provider.example/list.m3u']
    rows += ['Connect', 'Try demo mode']
    for i, r in enumerate(rows):
        y = 150 + i * 48
        if i == (len(rows) - 2):
            s.rect(340, y, 600, 48, ACC, ACC, 2, 4, op=0.9); s.text(358, y + 32, r, 22, '#fff', 700)
        else:
            s.rect(340, y, 600, 48, 'none', LINE, 1, 4); s.text(358, y + 32, r, 22, TXT if i else MUT)
    s.text(340, 150 + len(rows) * 48 + 40, 'OK on a row edits it (on-screen keyboard). OK on Source type switches Xtream / M3U.', 18, MUT)
    s.text(340, 150 + len(rows) * 48 + 66, 'Back leaves this screen once a library is already loaded.', 18, MUT)
    return s

def keyboard():
    s = S()
    s.rect(0, 0, 1280, 720, '#000', op=0.55)
    s.rect(300, 90, 680, 540, '#1E1E2E', LINE, 2, 10)
    s.text(340, 150, 'Server URL', 30, TXT, 700)
    s.rect(340, 175, 600, 56, '#0B0B12', ACC, 2, 4); s.text(356, 212, 'http://provider.example:8080', 24, TXT)
    rows = ['a b c d e f g h i j', 'k l m n o p q r s t', 'u v w x y z . / : -', '1 2 3 4 5 6 7 8 9 0']
    for r, line in enumerate(rows):
        for c, ch in enumerate(line.split()):
            x = 340 + c * 60; y = 260 + r * 56
            s.rect(x, y, 52, 48, SURF, LINE, 1, 4); s.text(x + 26, y + 32, ch, 22, TXT, 400, 'middle')
    s.rect(340, 500, 200, 52, ACC, ACC, 2, 4, op=0.9); s.text(440, 534, 'OK', 22, '#fff', 700, 'middle')
    s.rect(560, 500, 200, 52, 'none', LINE, 1, 4); s.text(660, 534, 'Cancel', 22, TXT, 400, 'middle')
    s.text(340, 590, "Roku's own keyboard dialog (StandardKeyboardDialog). The Roku phone app can type for you.", 17, MUT)
    s.text(640, 40, 'drawn over the screen that opened it', 17, MUT, 400, 'middle')
    return s

def browse(tab, status, cats, items, sel_cat=0, sel_item=0, focus='cats', star=(), no_cats=False):
    s = S(); chrome(s, status); tabs(s, tab, focus == 'tabs')
    if not no_cats: col(s, 260, 300, cats, sel_cat, focus == 'cats')
    col(s, 580, 670, items, sel_item, focus == 'items', star=star)
    s.line(250, 80, 250, 640, LINE); s.line(570, 80, 570, 640, LINE)
    return s

def screens():
    d = {}
    d['01-setup-xtream'] = setup_screen('xtream')
    d['02-setup-m3u'] = setup_screen('m3u')
    d['03-keyboard'] = keyboard()
    cats = ['All', 'News', 'Sports', 'Movies HD', 'Kids', 'Music', 'Documentary', 'Local']
    live = ['* Channel One HD', 'Channel Two', 'Sports Central', 'News 24', 'Kids Zone', 'Music Box', 'Docu Planet', 'Local 8']
    d['04-browse-live'] = browse(0, 'http://provider.example:8080   1,240 channels, 3,100 movies, 480 series', cats, live, 0, 0, 'items', star=(0,))
    d['05-browse-movies'] = browse(1, 'http://provider.example:8080   1,240 channels, 3,100 movies, 480 series',
        ['All', 'Action', 'Comedy', 'Drama', 'Family', 'Thriller', 'Sci-Fi'], ['Harbor Lights', 'Night Train', 'The Long Road', 'Paper Moon', 'Open Water', 'Second Chances', 'Low Tide'], 0, 2, 'items')
    d['06-episodes'] = browse(2, 'The Long Quiet: 9 episodes   (Back returns)',
        ['All', 'Drama', 'Mystery', 'Crime', 'Comedy'], ['S1 E1  Pilot', 'S1 E2  The Signal', 'S1 E3  Cold Open', 'S2 E1  Low Tide', 'S2 E2  Second Chances', 'S2 E3  The Harbor'], 0, 3, 'items')
    d['07-my-list'] = browse(3, 'Added to My List', [], ['* Harbor Lights', '* Channel One HD', '* The Long Quiet S1 E1', '* Big Buck Bunny'], None, 1, 'items', star=(0, 1, 2, 3), no_cats=True)
    d['08-search-results'] = browse(4, '12 results for "harbor"', [], ['Harbor Lights', 'Harbor Lights (4K)', 'Harbor News', 'The Harbor (S2 E3)'], None, 0, 'items', no_cats=True)
    d['09-settings'] = browse(5, 'Resume history cleared', [], ['Reload library', 'Change source', 'Clear My List', 'Clear resume history', 'About StreamBoss'], None, 3, 'items', no_cats=True)
    # playback
    p = S()
    p.rect(0, 0, 1280, 720, '#141428')
    p.rect(0, 0, 1280, 720, 'none', LINE, 1, dash='6 6')
    p.line(0, 0, 1280, 720, '#222238', 1); p.line(1280, 0, 0, 720, '#222238', 1)
    p.text(40, 52, 'Channel One HD', 28, '#fff', 700)
    p.text(40, 82, 'name shows for 3 seconds, then hides', 18, MUT)
    p.text(640, 380, 'video', 40, '#3a3a58', 400, 'middle')
    p.text(640, 690, 'Roku\'s standard player: OK pause/play, Left/Right skip, Back closes.  Live: Up next channel, Down previous.', 18, MUT, 400, 'middle')
    d['10-playback'] = p
    return d

def layout_spec():
    s = S(1280, 760)
    s.rect(0, 0, 1280, 720, BG, '#4b4b6b', 1)
    # safe area (about 5 percent)
    s.rect(64, 36, 1152, 648, 'none', '#6c6c9a', 1, dash='8 6')
    s.text(1210, 56, 'safe zone (about 5% in)', 14, '#6c6c9a', 400, 'end')
    zones = [
        ('brand', 40, 22, 240, 34, '#FF3D71', 'brand  Label (40,22)'),
        ('status', 290, 28, 940, 28, '#00B3A4', 'status  Label (290,28) w940'),
        ('tabs', 30, 80, 210, 322, '#7C5CFF', 'tabs  LabelList (30,80)\nitem 210x46, 6 rows'),
        ('cats', 260, 80, 300, 560, '#FFB020', 'cats  LabelList (260,80)\nitem 300x40, 14 rows\n(hidden on My List,\nSearch, Settings)'),
        ('items', 580, 80, 670, 560, '#30C48D', 'items  LabelList (580,80)\nitem 670x40, 14 rows\nup to 3000 shown'),
        ('hint', 40, 676, 1200, 28, '#00B3A4', 'hint  Label (40,676) w1200'),
    ]
    for _, x, y, w, h, c, label in zones:
        s.rect(x, y, w, h, c, c, 2, 4, op=0.14)
        for i, ln in enumerate(label.split('\n')):
            s.text(x + 10, y + 24 + i * 22, ln, 16, c, 700)
    s.text(640, 745, 'canvas 1280 x 720 (HD).  Setup screen: title (340,100); list (340,150) item 600x48, 8 rows.  Video + name label (40,30) cover everything while playing.', 15, MUT, 400, 'middle')
    return s

def flow():
    s = S(1280, 720)
    s.text(640, 44, 'Where focus goes', 28, TXT, 700, 'middle')
    def box(x, y, w, h, t, sub='', c=SURF, st=LINE):
        s.rect(x, y, w, h, c, st, 2, 8)
        s.text(x + w / 2, y + 32, t, 21, TXT, 700, 'middle')
        for i, ln in enumerate(sub.split('\n')):
            if ln: s.text(x + w / 2, y + 58 + i * 20, ln, 15, MUT, 400, 'middle')
    def lab(x, y, t, anchor='middle'): s.text(x, y, t, 15, MUT, 400, anchor)
    # start-up
    s.text(60, 90, 'START-UP', 14, ACC, 700)
    box(60, 105, 210, 80, 'Launch', 'reads the saved login')
    box(60, 255, 210, 80, 'Setup', 'type, URLs, login')
    box(60, 405, 210, 80, 'Connect', 'loads the library')
    s.path([(165, 185), (165, 255)]); lab(175, 224, 'no login saved', 'start')
    s.path([(60, 145), (30, 145), (30, 445), (60, 445)]); s.add('<text xml:space="preserve" transform="translate(22,300) rotate(-90)" font-size="15" fill="%s" text-anchor="middle">login saved</text>' % MUT)
    s.path([(165, 335), (165, 405)]); lab(175, 376, 'Connect', 'start')
    s.path([(270, 430), (300, 430), (300, 295), (270, 295)], dash='5 5'); lab(292, 360, 'fails', 'end')
    # browse
    s.text(390, 90, 'BROWSE', 14, ACC, 700)
    box(390, 105, 220, 100, 'Tabs', 'Live  Movies  Series\nMy List  Search  Settings', '#1E1E34', ACC)
    box(700, 105, 220, 100, 'Categories', 'All + the provider\'s\ncategories (Live,\nMovies, Series only)')
    box(1000, 105, 240, 100, 'Items', 'channels, titles,\nepisodes, results')
    s.path([(610, 140), (700, 140)]); lab(655, 128, 'Right / OK')
    s.path([(700, 175), (610, 175)]); lab(655, 196, 'Left / Back')
    s.path([(920, 140), (1000, 140)]); lab(960, 128, 'Right / OK')
    s.path([(1000, 175), (920, 175)]); lab(960, 196, 'Left / Back')
    s.path([(270, 455), (360, 455), (360, 155), (390, 155)]); lab(352, 420, 'loaded', 'end')
    # actions
    s.text(390, 280, 'ACTIONS', 14, ACC, 700)
    box(1000, 330, 240, 90, 'Player', 'full-screen video', '#141428')
    box(700, 330, 240, 90, 'Episodes', 'a series lists its episodes\n(Xtream sources only)')
    box(390, 330, 240, 90, 'Keyboard', 'Search, or a setup field')
    s.path([(1120, 205), (1120, 330)]); lab(1130, 262, 'OK on a channel', 'start'); lab(1130, 282, 'or a movie', 'start')
    s.path([(1040, 205), (1040, 262), (820, 262), (820, 330)]); lab(930, 254, 'OK on a series')
    s.path([(940, 375), (1000, 375)]); lab(970, 365, 'OK')
    s.path([(1160, 420), (1160, 470), (1060, 470), (1060, 205)], dash='5 5'); lab(1170, 460, 'Back', 'start')
    s.path([(500, 205), (500, 330)]); lab(510, 262, 'OK on Search', 'start')
    s.path([(630, 400), (680, 400), (680, 300), (1080, 300), (1080, 205)], dash='5 5'); lab(690, 292, 'results fill the list', 'start')
    s.path([(820, 420), (820, 500), (1030, 500), (1030, 205)], dash='5 5'); lab(830, 515, 'Back returns to the series list', 'start')
    # notes
    s.text(390, 600, 'OK on a Settings row runs it (Reload library, Change source, Clear My List, Clear resume history, About).', 16, MUT)
    s.text(390, 626, 'My List and Settings have no Categories column: Right goes from Tabs straight to Items.', 16, MUT)
    s.text(390, 652, '*  (Options) on an item adds or removes it from My List.   Back steps up: Items > Categories > Tabs.', 16, MUT)
    s.text(390, 678, 'Up/Down zap live channels while the video is on screen.   My List holds 40 titles, resume history 80.', 16, MUT)
    return s

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name, s in screens().items():
        open(f'{OUT}/{name}.svg', 'w').write(s.svg())
    open(f'{OUT}/11-layout-spec.svg', 'w').write(layout_spec().svg())
    open(f'{OUT}/12-focus-flow.svg', 'w').write(flow().svg())
    print(sorted(os.listdir(OUT)))
