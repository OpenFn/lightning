interface FileDropzoneHook {
  el: HTMLElement;
  destroy?: () => void;
  mounted(): void;
  destroyed(): void;
}

const FileDropzone = {
  mounted() {
    const dropzone = this.el;
    const targetSelector = dropzone.dataset['target'];
    if (!targetSelector) {
      console.error('No target selector specified');
      return;
    }

    const fileInput = document.querySelector<HTMLInputElement>(targetSelector);

    if (!fileInput) {
      console.error('Target file input not found:', targetSelector);
      return;
    }

    const highlight = () => {
      dropzone.classList.add('border-indigo-600', 'bg-indigo-50/50');
      dropzone.classList.remove('border-gray-900/25');
    };

    const unhighlight = () => {
      dropzone.classList.remove('border-indigo-600', 'bg-indigo-50/50');
      dropzone.classList.add('border-gray-900/25');
    };

    const handleDrop = (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();
      unhighlight();

      const dt = e.dataTransfer;
      if (!dt?.files) return;

      const files = dt.files;
      if (files.length > 0) {
        const file = files[0];
        if (!file) return;

        // Check if file is yaml/yml
        if (file.name.match(/\.(ya?ml)$/i)) {
          // Create a new FileList-like object
          const dataTransfer = new DataTransfer();
          dataTransfer.items.add(file);
          fileInput.files = dataTransfer.files;

          // Trigger change event to notify any listeners
          fileInput.dispatchEvent(new Event('change', { bubbles: true }));
        } else {
          console.error('Invalid file type. Please upload a YAML file.');
        }
      }
    };

    const handleDragEvent = (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();
      highlight();
    };

    const handleDragLeave = (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();
      unhighlight();
    };

    dropzone.addEventListener('dragenter', handleDragEvent);
    dropzone.addEventListener('dragover', handleDragEvent);
    dropzone.addEventListener('dragleave', handleDragLeave);
    dropzone.addEventListener('drop', handleDrop);

    // Cleanup
    this.destroy = () => {
      dropzone.removeEventListener('dragenter', handleDragEvent);
      dropzone.removeEventListener('dragover', handleDragEvent);
      dropzone.removeEventListener('dragleave', handleDragLeave);
      dropzone.removeEventListener('drop', handleDrop);
    };
  },

  destroyed() {
    if (this.destroy) {
      this.destroy();
    }
  },
} as FileDropzoneHook;

export default FileDropzone;
