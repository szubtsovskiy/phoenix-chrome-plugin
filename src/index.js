import "./styles/scss/index.scss";
import {Main} from './elm/Main.elm';

function app() {
    const root = document.createElement('div');
    Main.embed(root);
    return root;
}

(function(){
    document.body.appendChild(app());
})();
