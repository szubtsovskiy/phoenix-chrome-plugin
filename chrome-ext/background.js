function focusOrCreateTab(url) {
    chrome.windows.getAll({populate: true}, windows => {
        const existingTab = windows.reduce((found, w) => found || w.tabs.find(t => t.url === url), null);
        if (existingTab) {
            chrome.windows.update(existingTab.windowId, {focused: true});
            chrome.tabs.update(existingTab.id, {selected: true});
        } else {
            chrome.tabs.create({url: url, selected: true});
        }
    });
}

chrome.browserAction.onClicked.addListener(() => {
    const indexUrl = chrome.extension.getURL("index.html");
    focusOrCreateTab(indexUrl);
});
