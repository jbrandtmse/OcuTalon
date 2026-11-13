import { Directive, ElementRef, Renderer2, effect, inject, model, output, signal } from '@angular/core';

/**
 * A drop target for files (UX-DR129: a second way beside a button, never the only one). While `active` is true the element takes a drag that carries
 * files: it sets the class `dragging` while one is over it (the page draws an outline from it) and gives the files of a drop to `files`, which
 * ends the drag. While `active` is false it binds no handler at all, so the browser's own handling of a drop stays as it is. A drag that carries no
 * files is left alone. The Documents page and the chat use it.
 */
@Directive({
  selector: '[appFileDrop]',
  host: { '[class.dragging]': 'dragging()' },
})
export class FileDrop {
  /** Whether the element takes drops; a template binds it, and a component that uses the directive as a host directive sets it. */
  readonly active = model(true);
  /** The files of a drop, in the order the browser gave them. */
  readonly files = output<File[]>();

  protected readonly dragging = signal(false);

  constructor() {
    const host = inject<ElementRef<HTMLElement>>(ElementRef).nativeElement;
    const renderer = inject(Renderer2);
    effect((onCleanup) => {
      if (!this.active()) {
        this.dragging.set(false);
        return;
      }
      const stops = [
        renderer.listen(host, 'dragover', (event: DragEvent) => this.dragOver(event)),
        renderer.listen(host, 'dragleave', (event: DragEvent) => this.dragLeave(event)),
        renderer.listen(host, 'drop', (event: DragEvent) => this.dropped(event)),
      ];
      onCleanup(() => stops.forEach((stop) => stop()));
    });
  }

  private dragOver(event: DragEvent): void {
    if (event.dataTransfer?.types.includes('Files')) {
      event.preventDefault();
      this.dragging.set(true);
    }
  }

  private dragLeave(event: DragEvent): void {
    const host = event.currentTarget as HTMLElement;
    if (!(event.relatedTarget instanceof Node) || !host.contains(event.relatedTarget)) {
      this.dragging.set(false);
    }
  }

  private dropped(event: DragEvent): void {
    if (!event.dataTransfer?.types.includes('Files')) {
      return;
    }
    event.preventDefault();
    this.dragging.set(false);
    this.files.emit(Array.from(event.dataTransfer?.files ?? []));
  }
}
