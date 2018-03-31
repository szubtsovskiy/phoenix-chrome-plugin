import "./styles/scss/index.scss";
import {Main} from './elm/Main.elm';
import {Socket} from "./vendor/phoenix";
import JSONFormatter from 'json-formatter-js';
import 'arrive';


function app() {
    let ws;
    let channel;
    const root = document.createElement('div');
    const app = Main.embed(root);
    app.ports.connect.subscribe(url => {
        if (ws) {
            ws.disconnect();
        }
        ws = new Socket(url);
        ws.onOpen(() => app.ports.connections.send(url));
        ws.connect();
    });
    app.ports.join.subscribe(topic => {
        channel = ws.channel(topic);
        channel.onMessage = (event, payload) => {
            app.ports.messages.send([event, payload || null]);
            return payload;
        };
        channel.join()
            .receive("ok", () => {
                app.ports.joins.send(topic);
            })
            .receive("error", () => {

            });
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
            const preview = (function() {
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
