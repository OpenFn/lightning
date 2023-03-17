// The drag mask stops the cursor interacting with the page while dragging
const addDragMask = () => {
  const dragMask = document.createElement('div');
  dragMask.id = 'drag-mask';
  dragMask.style.position = 'absolute';
  dragMask.style.left = '0';
  dragMask.style.right = '0';
  dragMask.style.top = '0';
  dragMask.style.bottom = '0';
  dragMask.style.userSelect = 'none';
  dragMask.style.zIndex = '999';
  dragMask.style.cursor = 'ew-resize';
  document.body.appendChild(dragMask);
};

interface ResizerHook {
  el: HTMLElement;
  container: HTMLElement;
  mounted(): void;
  destroyed(): void;

  onPointerDown(): void;
  onPointerUp(): void;
  onPointerMove(): void;
  dragListener?(): void;

  containerBounds: DOMRect;
  width?: number;
}

const hook = {
  onPointerDown(this: ResizerHook, e: any) {
    this.containerBounds = this.container.getBoundingClientRect();
    addDragMask();

    const onMove = e => this.onPointerMove(e);
    document.addEventListener('pointermove', onMove);
    document.addEventListener(
      'pointerup',
      () => {
        document.removeEventListener('pointermove', onMove);
        this.onPointerUp();
      },
      {
        once: true,
      }
    );
  },
  onPointerUp(this: ResizerHook) {
    const mask = document.getElementById('drag-mask');
    if (mask) {
      (mask.parentNode as HTMLElement).removeChild(mask);
      if (this.width) {
        localStorage.setItem('lightning.job-editor.width', `${this.width}`);
      }
      // triggers a layout in monaco
      document.dispatchEvent(new Event('update-layout'));
    }
  },
  onPointerMove(this: ResizerHook, e: any) {
    const parent = this.el.parentNode! as HTMLElement;
    const { width: containerWidth, left: containerLeft } = this.containerBounds;
    if (e.screenX !== 0) {
      // Work out the mouse position relative to the parent
      const relativePosition = Math.max(
        0,
        Math.min((e.clientX - containerLeft) / containerWidth)
      );
      // Invert the postion
      this.width = (1 - relativePosition) * 100;
      // Update the width
      parent.style.width = `${this.width}%`;
    }
  },
  mounted(this: ResizerHook) {
    const parent = this.el.parentNode! as HTMLElement;

    let container: HTMLElement = parent;
    while (container && !container.className.match('h-full')) {
      container = container.parentNode as HTMLElement;
    }
    this.container = container;

    const savedWidth = localStorage.getItem('lightning.job-editor.width');
    if (parent) {
      if (savedWidth) {
        parent.style.width = `${savedWidth}%`;
      }
    }
    this.el.addEventListener('pointerdown', e => this.onPointerDown(e));
  },
} as ResizerHook;

export default hook;
