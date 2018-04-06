import "./styles/index.scss";
import {Main} from './elm/Main.elm';
import {Socket} from "./javascript/vendor/phoenix";
import JSONFormatter from 'json-formatter-js';
import 'arrive';
import AutoComplete from './javascript/vendor/auto-complete';

function app() {
    let ws;
    let channel;
    const history = {};
    const root = document.createElement('div');
    const app = Main.embed(root);
    app.ports.connect.subscribe(([url, topic]) => {
        if (ws) {
            ws.disconnect();
        }
        ws = new Socket(url);
        ws.onOpen(() => {
            channel = ws.channel(topic);
            channel.onMessage = (event, payload) => {
                app.ports.messages.send([event, payload || null]);
                return payload;
            };
            channel.join()
                .receive("ok", () => {
                    app.ports.connections.send(null);
                })
                .receive("error", err => {
                    app.ports.connections.send(err.reason || 'unknown error');
                });
        });
        ws.connect();
    });
    app.ports.disconnect.subscribe(() => {
        if (ws) {
            ws.disconnect();
        }
    });
    app.ports.send.subscribe(([event, payload]) => {
        let pushPayload;
        try {
            pushPayload = JSON.parse(payload);
        } catch (e) {
            if (e instanceof SyntaxError) {
                pushPayload = payload;
            } else {
                throw e;
            }
        }
        channel.push(event, pushPayload);
    });
    app.ports.previews.subscribe(({containerID, data}) => {
        document.arrive(`#${containerID}`, {onlyOnce: true, existing: true}, container => {
            const preview = (function () {
                if (data == null || (typeof data !== 'object' && typeof data !== 'string')) {
                    const preview = document.createElement('div');
                    preview.className = 'fully-centered';
                    preview.appendChild(document.createTextNode('Nothing to show'));
                    return preview;
                } else if (typeof data === 'object') {
                    return new JSONFormatter(data, Infinity).render();
                } else {
                    try {
                        return new JSONFormatter(JSON.parse(data), Infinity).render();
                    } catch (_) {
                        return document.createTextNode(data);
                    }
                }
            })();

            container.innerHTML = '';
            container.appendChild(preview);
        });
    });
    app.ports.copy.subscribe(message => {
        const input = document.createElement('input');
        input.type = 'text';
        input.style.width = '10px';
        input.style.height = '10px';
        input.style.position = 'absolute';
        input.style.left = '-100px';
        document.body.appendChild(input);
        input.value = message;
        input.select();
        document.execCommand('copy');
        document.body.removeChild(input);

    });
    app.ports.autoComplete.subscribe(id => {
        document.arrive(`#${id}`, {onlyOnce: true, existing: true}, input => {
            new AutoComplete({
                selector: input,
                minChars: 0,
                cache: false,
                source: function (term, suggest) {
                    term = term.toLowerCase();
                    const choices = history[input.id] || [];
                    const matches = choices.filter(choice => ~choice.toLowerCase().indexOf(term));
                    suggest(matches);
                },
                onSelect: (e, term) => {
                    e.stopPropagation();
                    const inputEvent = new Event('input');
                    inputEvent.targetValue = term;
                    input.dispatchEvent(inputEvent);
                },
                renderItem : (item, search) => {
                    search = search.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');
                    const suggestionValue = item.replace(/"/g, '&quot;');
                    const suggestionText = item.replace(new RegExp(`(${search.split(' ').join('|')})`, "gi"), "<b>$1</b>");
                    return `<div class="autocomplete-suggestion" data-val="${suggestionValue}">${suggestionText}</div>`;
                }
            });
        });
    });
    app.ports.choices.subscribe(([id, choices]) => {
        history[id] = choices;
    });
    return root;
}

(function () {
    const script = document.body.querySelector('script');
    if (script) {
        document.body.insertBefore(app(), script);
    } else {
        document.body.appendChild(app());
    }
})();
