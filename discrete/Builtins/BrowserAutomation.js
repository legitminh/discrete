/* Native browser scripting only: no JavaScript is evaluated inside webpages.
 * All user data arrives as argv/JSON, never as executable script source. */
function run(argv) {
    var browser = Application(argv[0]);
    var safari = argv[0] === 'com.apple.Safari';
    var operation = argv[1];
    if (operation === 'front') {
        var windows = browser.windows();
        return JSON.stringify(windows.length ? String(windows[0].id()) : '');
    }
    if (operation === 'scan') {
        if (!browser.running()) return '[]';
        return JSON.stringify(browser.windows().map(function (window) {
            var tabs = window.tabs();
            var active = safari ? window.currentTab.index() : window.activeTabIndex();
            var bounds = window.bounds();
            return {
                id: String(window.id()), index: window.index(), activeTab: active,
                bounds: [bounds.x, bounds.y, bounds.width, bounds.height],
                tabs: tabs.map(function (tab, index) {
                    return {index: index + 1, url: tab.url() || '', title: safari ? tab.name() : tab.title()};
                })
            };
        }));
    }
    if (operation === 'select') {
        var choice = JSON.parse(argv[2]);
        var windows = browser.windows();
        var window = windows.filter(function (item) { return String(item.id()) === choice.windowID; })[0];
        if (!window) throw new Error('The selected browser window was closed. Try again.');
        var tab = window.tabs()[choice.tabIndex - 1];
        // A tab may close or move while the scan is in progress. Never select
        // an unrelated page after the tab strip changes.
        if (!tab || tab.url() !== choice.url) throw new Error('The browser tabs changed. Try again.');
        if (safari) window.currentTab = tab;
        else window.activeTabIndex = choice.tabIndex;
        if (safari) {
            window.miniaturized = false;
            window.visible = true;
        } else window.minimized = false;
        window.index = 1;
        browser.activate();
        return 'selected';
    }
    if (operation === 'new') {
        var windows = browser.windows();
        if (!windows.length) {
            if (safari) {
                browser.documents.push(browser.Document({url: argv[2]}));
            } else {
                var created = browser.Window();
                browser.windows.push(created);
                created.activeTab.url = argv[2];
            }
        } else {
            var window = windows[0];
            var tab = browser.Tab({url: argv[2]});
            window.tabs.push(tab);
            if (safari) {
                window.currentTab = tab;
                window.miniaturized = false;
                window.visible = true;
            } else {
                window.activeTabIndex = window.tabs.length;
                window.minimized = false;
            }
            window.index = 1;
        }
        browser.activate();
        return 'opened';
    }
    throw new Error('Unknown browser operation.');
}
