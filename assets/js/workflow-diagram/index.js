// Hook for Workflow Diagram Component
// `component.jsx` is imported dynamically, saving loading React
// and all the other dependencies until they are needed.

export default {
  mounted() {
    import("./component").then(({ mount }) => {
      this.component = mount(this.el);
      this.handleEvent("update_project_space", (projectSpace) => {
        this.component.update({
          projectSpace,
          onNodeClick: (_event, node) => {
            if (node.data.type == "job") {
              this.selectNode(node.data.id);
            }
          },
          onPaneClick: (_event) => {
            this.unselectNode();
          },
        });
      });
      this.pushEventTo(this.el, "component_mounted");
    });
  },
  destroyed() {
    this.component.unmount();
  },
  // Add `?selected=<id>` to the URL.
  selectNode(id) {
    const currentURL = new URL(window.location.href);
    currentURL.search = `?selected=${id}`;
    this.liveSocket.pushHistoryPatch(currentURL.toString(), "push", this.el);
  },
  // Remove `?selected=<id>` from the URL.
  unselectNode() {
    const currentURL = new URL(window.location.href);
    const searchParams = new URLSearchParams(currentURL.search);
    if (searchParams.has("selected")) {
      searchParams.delete("selected");
      currentURL.search = `?${searchParams.toString()}`;
      this.liveSocket.pushHistoryPatch(currentURL.toString(), "push", this.el);
    }
  },
};
