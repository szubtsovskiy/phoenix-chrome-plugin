import "./styles/scss/index.scss";
import {Main} from './elm/Main.elm';
import {Socket} from "./vendor/phoenix";
import JSONFormatter from 'json-formatter-js';
import 'arrive';


function app() {
    let ws;
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
        let channel = ws.channel(topic);
        channel.onMessage = (event, payload) => {
            app.ports.messages.send([event, payload]);
            return payload;
        };
        channel.join()
            .receive("ok", () => {
                app.ports.joins.send(topic);
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
                })
            })
            .receive("error", () => {

            });
    });
    app.ports.previews.subscribe(({containerID, data}) => {
        document.arrive(`#${containerID}`, {onlyOnce: true, existing: true}, container => {
            const preview = (function() {
                switch (typeof data) {
                    case 'object':
                        return new JSONFormatter(data, Infinity).render();
                    case 'string':
                        try {
                            return new JSONFormatter(JSON.parse(data), Infinity).render();
                        } catch (_) {
                            return document.createTextNode(data);
                        }
                    default:
                        return document.createTextNode("");

                }
            })();

            container.innerHTML = '';
            container.appendChild(preview);
        });
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
