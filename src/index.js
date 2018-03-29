import "./styles/scss/index.scss";
import {Main} from './elm/Main.elm';

function app() {
    const root = document.createElement('div');
    Main.embed(root);
    return root;
}

(function(){
    const script = document.body.querySelector('script');
    if (script) {
        document.body.insertBefore(app(), script);
    } else {
        document.body.appendChild(app());
    }
})();
