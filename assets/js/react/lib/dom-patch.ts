import morphdom from 'morphdom';

// They don't export the type of their options 😠
type MorphDomOptions = NonNullable<Parameters<typeof morphdom>[2]>;

export const createMorphdomOptions = (
  // `DOMPatch` is the internal class in Phoenix LiveView that calls morphdom
  debugName = 'DOMPatch'
) =>
  ({
    childrenOnly: true,
    // @ts-expect-error -- this option is missing in their typedef but it's in their docs
    addChild: (parentNode: Node, childNode: Node) => {
      console.debug(`${debugName} addChild`, { parentNode, childNode });
      return parentNode.appendChild(childNode);
    },
    onBeforeNodeAdded: node => {
      console.debug(`${debugName} onBeforeNodeAdded`, { node });
      return node;
    },
    onBeforeElUpdated: (fromEl, toEl) => {
      console.debug(`${debugName} onBeforeElUpdated`, { fromEl, toEl });

      // https://github.com/patrick-steele-idem/morphdom/blob/master/README.md#can-i-make-morphdom-blaze-through-the-dom-tree-even-faster-yes
      return !fromEl.isEqualNode(toEl);
    },
    onElUpdated: el => {
      console.debug(`${debugName} onElUpdated`, { el });
    },
    onBeforeNodeDiscarded: node => {
      console.debug(`${debugName} onBeforeNodeDiscarded`, { node });
      return true;
    },
    onNodeDiscarded: node => {
      console.debug(`${debugName} onNodeDiscarded`, { node });
    },
    onBeforeElChildrenUpdated: (fromEl, toEl) => {
      console.debug(`${debugName} onBeforeElChildrenUpdated`, { fromEl, toEl });
      return true;
    },
  }) satisfies MorphDomOptions;

const patchDomOptions = createMorphdomOptions('morphdom');

// inspired by deps/phoenix_live_view/assets/js/phoenix_live_view/dom_patch.js
export const domPatch = (targetContainer: HTMLElement, source: string | Node) =>
  morphdom(targetContainer, source, patchDomOptions);
