// Hook for Workflow Diagram Component
export default {
  mounted() {
    import("./component").then(({ mount }) => {
      this.component = mount(this.el);
      this.handleEvent("update_project_space", (payload) => {
        this.component.update(payload);
      });
      this.pushEventTo(this.el, "component.mounted");
    });
  },
  destroyed() {
    this.component.unmount();
  },
};
