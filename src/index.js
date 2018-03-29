import "./styles/scss/index.scss";
import {Main} from './elm/Main.elm';
import {Socket} from "./vendor/phoenix";

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
        channel.onMessage = (event, payload, ref) => {
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
