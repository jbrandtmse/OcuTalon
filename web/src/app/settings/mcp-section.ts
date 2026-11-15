import { afterNextRender, ChangeDetectionStrategy, Component, DestroyRef, ElementRef, inject, Injector, computed, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpErrorResponse } from '@angular/common/http';
import { Observable, tap } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { McpSettings, McpSourceRow, McpToolRow } from '../api/api-types';
import { Icon } from '../icon/icon';
import { LOAD_FAILED } from '../live/live-state';
import { intervalText } from '../rail/rail-view';
import { Announcer } from '../shared/announcer';
import { CONFIRM_TITLE_ID, CONFIRMED, ConfirmDialog, ConfirmRequest } from '../shared/confirm-dialog';
import { Dialogs } from '../shared/dialogs';
import { ServerButton } from '../shared/server-button';
import {
  addBody,
  canBeSource,
  changedTools,
  CLASSIFICATION_OPTIONS,
  classificationName,
  DEFAULT_INTERVAL,
  INTERVAL_CHOICES,
  MCP_TEXTS,
  mcpOutcome,
  removeName,
  removeQuestion,
  removeSourceName,
  sourceBody,
  sourceName,
  sourceOutcome,
  statusText,
  toolChangedText,
  toolKey,
  toolStatusText,
  toolText,
  visibleTools,
  withClassification,
  withoutChange,
} from './mcp-view';
import { SETTINGS_TEXTS } from './settings-view';

/** What one tool row shows beside its radiogroup: the "Saved" line or the error that put the old value back. */
interface RowState {
  saved: boolean;
  error: string;
}

const BLANK: RowState = { saved: false, error: '' };

/** The settings before the list has answered. */
const NONE: McpSettings = { servers: [], tools: [], sources: [] };

/**
 * The Tools and MCP servers section of Settings (Story 21.4; FR-47, FR-48): the admin's MCP servers with an Add server form and a confirmed Remove, and the tools
 * of all of them with a classification radiogroup each. The server judges every value and the section shows its answers as they come (AD-12):
 *   - the list is GET /v1/settings/mcp (the servers and the tools, never a secret). A 403 shows the page's denied text in place of the content, a 409 `not_available`
 *     (the online demo) shows its own line in place of the content, and any other failure shows the accepted load error with Retry;
 *   - Add server posts the name, the address and, when one was typed, the secret (a password field: write-only, cleared once the server has it). A 200 shows the
 *     server's message, empties the fields and loads the list again; a 400 `bad_mcp_server` shows the text of each refused field under it and focuses the first;
 *     any other failure shows the server's message under the button, and the list is loaded again;
 *   - Remove opens the page's confirm dialog with the sentence for the server's tool count and pending request count (UX-DR38: the sentence names the dialog and
 *     takes its first focus). A 200 or a 404 closes it and the server and its tools leave the lists; any other answer leaves it open with the server's message;
 *   - a radiogroup pick saves at once: the radio shows the new value and the check icon, "Saved" shows for that row and is announced; a failure puts the old value
 *     back and shows the server's message. A row that was just classified stays in the "Unclassified only" list until the section is opened again.
 *   - a tool whose `changed` is true and whose status is not refused has a warning banner above the tools table, in the words of settings.toolChangedBanner (Story
 *     21.9); a successful classification save takes it away, and a failed one keeps it. A new Unclassified tool and a refused one have none.
 *   - Use as a source (Story 21.5): a Read-only tool's Source button opens a form below the table (Source name, Arguments (JSON), Check every) that posts the source; a tool that is
 *     not Read-only has the button aria-disabled with the accepted reason beside it, and a refused tool has none. A 400 `bad_source` shows each refused field's text under its field
 *     and focuses the first; a refused tool and any other failure show the server's message under the buttons. A 200 announces "Saved", closes the form, returns focus to the
 *     tool's button and loads the list again. "Your sources" lists the session's own sources, each with a Remove that acts at once.
 * Typing in a field clears its error and the line of the last add. The section takes no part in the page's unsaved guard: nothing in it is kept on leaving.
 */
@Component({
  selector: 'app-mcp-section',
  imports: [Icon, ServerButton],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @switch (state()) {
      @case ('off') {
        <p class="help" data-state="off">{{ texts.offOnDemo }}</p>
      }
      @case ('failed') {
        <div class="load-error" data-state="failed">
          <p class="load-error-text" id="mcp-load-error-text">{{ loadFailed }}</p>
          <app-server-button variant="secondary" [action]="retry" [describedBy]="['mcp-load-error-text']">Retry</app-server-button>
        </div>
      }
      @case ('denied') {
        <p class="field-error" data-state="denied"><app-icon name="circle-alert" [size]="16" />{{ denied }}</p>
      }
      @case ('ready') {
        <section class="group" aria-labelledby="mcp-servers-heading" data-group="servers">
          <h3 id="mcp-servers-heading" class="heading" tabindex="-1">{{ texts.servers }}</h3>
          @if (settings().servers.length === 0) {
            <p class="help" data-empty="servers">{{ texts.noServers }}</p>
          } @else {
            <div class="scroll">
              <table class="table" aria-labelledby="mcp-servers-heading">
                <thead>
                  <tr>
                    <th scope="col">{{ texts.columns.server }}</th>
                    <th scope="col">{{ texts.columns.address }}</th>
                    <th scope="col">{{ texts.columns.status }}</th>
                    <th scope="col" class="number">{{ texts.columns.tools }}</th>
                    <th scope="col" class="number">{{ texts.columns.unclassified }}</th>
                    <td></td>
                  </tr>
                </thead>
                <tbody>
                  @for (server of settings().servers; track server.name) {
                    <tr [attr.data-server]="server.name">
                      <th scope="row" class="name">{{ server.name }}</th>
                      <td class="address">{{ server.address }}</td>
                      <td>{{ statusOf(server.status) }}</td>
                      <td class="number">{{ server.tools }}</td>
                      <td class="number">{{ server.unclassified }}</td>
                      <td>
                        <button type="button" class="button button-secondary" [attr.aria-label]="removeNameOf(server.name)" (click)="askRemove(server.name, server.tools, server.pending, $event)">
                          {{ texts.removeButton }}
                        </button>
                      </td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
            <p class="help">{{ texts.statusHelp }}</p>
          }
          <div class="form" role="group" aria-labelledby="mcp-add-heading">
            <h4 id="mcp-add-heading" class="subheading">{{ texts.addServer }}</h4>
            <div class="field">
              <label for="mcp-name">{{ texts.form.name }}</label>
              <input
                id="mcp-name"
                class="input"
                type="text"
                autocomplete="off"
                [class.invalid]="nameError() !== ''"
                [attr.aria-invalid]="nameError() !== '' ? 'true' : null"
                [attr.aria-describedby]="nameError() !== '' ? 'mcp-name-error' : null"
                [value]="name()"
                (input)="typed('name', $event)"
              />
              @if (nameError() !== '') {
                <p class="field-error" id="mcp-name-error"><app-icon name="circle-alert" [size]="16" />{{ nameError() }}</p>
              }
            </div>
            <div class="field">
              <label for="mcp-address">{{ texts.form.address }}</label>
              <input
                id="mcp-address"
                class="input"
                type="text"
                autocomplete="off"
                [class.invalid]="addressError() !== ''"
                [attr.aria-invalid]="addressError() !== '' ? 'true' : null"
                [attr.aria-describedby]="addressError() !== '' ? 'mcp-address-error' : null"
                [value]="address()"
                (input)="typed('address', $event)"
              />
              @if (addressError() !== '') {
                <p class="field-error" id="mcp-address-error"><app-icon name="circle-alert" [size]="16" />{{ addressError() }}</p>
              }
            </div>
            <div class="field">
              <label for="mcp-secret">{{ texts.form.secret }}</label>
              <input
                id="mcp-secret"
                class="input"
                type="password"
                autocomplete="off"
                [class.invalid]="secretError() !== ''"
                [attr.aria-invalid]="secretError() !== '' ? 'true' : null"
                [attr.aria-describedby]="secretError() !== '' ? 'mcp-secret-help mcp-secret-error' : 'mcp-secret-help'"
                [value]="secret()"
                (input)="typed('secret', $event)"
              />
              <p class="help" id="mcp-secret-help">{{ texts.form.secretHelp }}</p>
              @if (secretError() !== '') {
                <p class="field-error" id="mcp-secret-error"><app-icon name="circle-alert" [size]="16" />{{ secretError() }}</p>
              }
            </div>
            <div class="actions">
              <app-server-button variant="primary" [action]="add" [describedBy]="addDescribed()">{{ texts.addServer }}</app-server-button>
            </div>
            @if (addError() !== '') {
              <p class="field-error" id="mcp-add-error"><app-icon name="circle-alert" [size]="16" />{{ addError() }}</p>
            }
            @if (addDone() !== '') {
              <p class="saved" data-saved="add">{{ addDone() }}</p>
            }
          </div>
        </section>
        <section class="group" aria-labelledby="mcp-tools-heading" data-group="tools">
          <h3 id="mcp-tools-heading" class="heading">{{ texts.tools }}</h3>
          @for (tool of changed(); track key(tool)) {
            <div class="banner" data-banner="tool-changed" [attr.data-tool]="tool.name" [attr.data-server]="tool.server">
              <app-icon class="mark" name="triangle-alert" [size]="20" />
              <span class="text">{{ changedText(tool) }}</span>
            </div>
          }
          <label class="check">
            <input type="checkbox" [checked]="onlyUnclassified()" (change)="toggleOnly($event)" />
            {{ texts.unclassifiedOnly }}
          </label>
          @if (visible().length === 0) {
            <p class="help" data-empty="tools">{{ onlyUnclassified() ? texts.noUnclassified : texts.noTools }}</p>
          } @else {
            <div class="scroll">
              <table class="table" aria-labelledby="mcp-tools-heading">
                <thead>
                  <tr>
                    <th scope="col">{{ texts.toolColumns.tool }}</th>
                    <th scope="col">{{ texts.toolColumns.server }}</th>
                    <th scope="col">{{ texts.toolColumns.status }}</th>
                    <th scope="col">{{ texts.toolColumns.classification }}</th>
                    <th scope="col">{{ texts.toolColumns.source }}</th>
                  </tr>
                </thead>
                <tbody>
                  @for (tool of visible(); track key(tool); let index = $index) {
                    <tr [attr.data-tool]="tool.name" [attr.data-server]="tool.server">
                      <th scope="row" class="name">{{ tool.name }}</th>
                      <td>{{ tool.server }}</td>
                      <td>{{ toolStatusOf(tool.status) }}</td>
                      <td>
                        <div class="radios" role="radiogroup" [attr.aria-label]="groupName(tool)">
                          @for (option of options; track option.value) {
                            <label class="radio">
                              <input type="radio" [name]="'mcp-class:' + tool.server + ':' + tool.name" [value]="option.value" [checked]="tool.classification === option.value" (change)="pick(tool, option.value)" />
                              <span [class]="'chip chip-' + option.value">{{ option.label }}</span>
                              @if (tool.classification === option.value) {
                                <app-icon class="selected" name="check" [size]="16" />
                              }
                            </label>
                          }
                        </div>
                        @if (rowState(tool).saved) {
                          <p class="saved" data-saved="classify">{{ texts.saved }}</p>
                        }
                        @if (rowState(tool).error !== '') {
                          <p class="field-error"><app-icon name="circle-alert" [size]="16" />{{ rowState(tool).error }}</p>
                        }
                      </td>
                      <td>
                        @if (tool.status !== 'refused') {
                          @if (sourceable(tool)) {
                            <button type="button" class="button button-secondary" data-source-button [attr.data-key]="key(tool)" [attr.aria-label]="sourceNameOf(tool)" (click)="openSource(tool)">
                              {{ texts.sourceHeading }}
                            </button>
                          } @else {
                            <button
                              type="button"
                              class="button button-secondary"
                              data-source-button
                              aria-disabled="true"
                              [attr.data-key]="key(tool)"
                              [attr.aria-label]="sourceNameOf(tool)"
                              [attr.aria-describedby]="'mcp-source-why-' + index"
                            >
                              {{ texts.sourceHeading }}
                            </button>
                            <p class="help" [id]="'mcp-source-why-' + index">{{ texts.sourceNotReadOnly }}</p>
                          }
                        }
                      </td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          }
          @if (sourceFor(); as target) {
            <div class="form" role="group" aria-labelledby="mcp-source-heading" data-form="source">
              <h4 id="mcp-source-heading" class="subheading">{{ texts.sourceHeading }}</h4>
              <p class="help">{{ toolTextOf(target.tool, target.server) }}</p>
              <p class="help">{{ texts.sourceHelp }}</p>
              <div class="field">
                <label for="mcp-source-name">{{ texts.sourceName }}</label>
                <input
                  id="mcp-source-name"
                  class="input"
                  type="text"
                  maxlength="100"
                  autocomplete="off"
                  [class.invalid]="sourceNameError() !== ''"
                  [attr.aria-invalid]="sourceNameError() !== '' ? 'true' : null"
                  [attr.aria-describedby]="sourceNameError() !== '' ? 'mcp-source-name-error' : null"
                  [value]="sourceNameValue()"
                  (input)="typedSource('name', $event)"
                />
                @if (sourceNameError() !== '') {
                  <p class="field-error" id="mcp-source-name-error"><app-icon name="circle-alert" [size]="16" />{{ sourceNameError() }}</p>
                }
              </div>
              <div class="field">
                <label for="mcp-source-arguments">{{ texts.sourceArguments }}</label>
                <textarea
                  id="mcp-source-arguments"
                  class="input"
                  rows="4"
                  autocomplete="off"
                  spellcheck="false"
                  [class.invalid]="sourceArgumentsError() !== ''"
                  [attr.aria-invalid]="sourceArgumentsError() !== '' ? 'true' : null"
                  [attr.aria-describedby]="sourceArgumentsError() !== '' ? 'mcp-source-arguments-error' : null"
                  [value]="sourceArguments()"
                  (input)="typedSource('arguments', $event)"
                ></textarea>
                @if (sourceArgumentsError() !== '') {
                  <p class="field-error" id="mcp-source-arguments-error"><app-icon name="circle-alert" [size]="16" />{{ sourceArgumentsError() }}</p>
                }
              </div>
              <div class="field">
                <label for="mcp-source-interval">{{ texts.sourceInterval }}</label>
                <select
                  id="mcp-source-interval"
                  class="input"
                  [attr.aria-invalid]="sourceIntervalError() !== '' ? 'true' : null"
                  [attr.aria-describedby]="sourceIntervalError() !== '' ? 'mcp-source-interval-error' : null"
                  (change)="typedSource('interval', $event)"
                >
                  @for (choice of intervals; track choice.value) {
                    <option [value]="choice.value" [selected]="choice.value === sourceInterval()">{{ choice.label }}</option>
                  }
                </select>
                @if (sourceIntervalError() !== '') {
                  <p class="field-error" id="mcp-source-interval-error"><app-icon name="circle-alert" [size]="16" />{{ sourceIntervalError() }}</p>
                }
              </div>
              <div class="actions">
                <app-server-button variant="primary" [action]="saveSource" [describedBy]="sourceDescribed()">{{ saveText }}</app-server-button>
                <button type="button" class="button button-secondary" (click)="closeSource(true)">{{ texts.cancel }}</button>
              </div>
              @if (sourceError() !== '') {
                <p class="field-error" id="mcp-source-error"><app-icon name="circle-alert" [size]="16" />{{ sourceError() }}</p>
              }
            </div>
          }
          @if (sourceDone() !== '') {
            <p class="saved" data-saved="source">{{ sourceDone() }}</p>
          }
        </section>
        <section class="group" aria-labelledby="mcp-sources-heading" data-group="sources">
          <h3 id="mcp-sources-heading" class="heading" tabindex="-1">{{ texts.sources }}</h3>
          @if (settings().sources.length === 0) {
            <p class="help" data-empty="sources">{{ texts.noSources }}</p>
          } @else {
            <div class="scroll">
              <table class="table" aria-labelledby="mcp-sources-heading">
                <thead>
                  <tr>
                    <th scope="col">{{ texts.sourceColumns.source }}</th>
                    <th scope="col">{{ texts.sourceColumns.tool }}</th>
                    <th scope="col">{{ texts.sourceColumns.interval }}</th>
                    <td></td>
                  </tr>
                </thead>
                <tbody>
                  @for (source of settings().sources; track source.ref) {
                    <tr [attr.data-source]="source.name">
                      <th scope="row" class="name">{{ source.name }}</th>
                      <td>{{ toolTextOf(source.tool, source.server) }}</td>
                      <td>{{ intervalOf(source.intervalMinutes) }}</td>
                      <td>
                        <button type="button" class="button button-secondary" [attr.aria-label]="removeSourceNameOf(source)" (click)="removeSource(source)">
                          {{ texts.removeButton }}
                        </button>
                      </td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          }
          @if (sourcesError() !== '') {
            <p class="field-error" data-error="sources"><app-icon name="circle-alert" [size]="16" />{{ sourcesError() }}</p>
          }
        </section>
      }
    }
  `,
  styles: `
    :host {
      display: block;
    }
    .group {
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
      margin-top: var(--space-6);
    }
    .heading,
    .subheading {
      margin: 0;
      color: var(--ink);
    }
    .scroll {
      overflow-x: auto;
      scroll-padding: var(--space-scroll-gutter);
    }
    .table {
      width: 100%;
      border-collapse: collapse;
      color: var(--ink);
    }
    .table th,
    .table td {
      padding: var(--space-2) var(--space-3);
      border-bottom: var(--text-input-border);
      text-align: left;
      vertical-align: top;
      font-weight: inherit;
    }
    .table thead th {
      font-weight: 600;
    }
    .table .name {
      font-weight: 600;
    }
    .table .number {
      text-align: right;
    }
    .address {
      overflow-wrap: anywhere;
    }
    .form {
      display: flex;
      flex-direction: column;
      gap: var(--space-3);
      max-width: 480px;
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .input {
      box-sizing: border-box;
      width: 100%;
      min-height: var(--space-target-min);
      padding: var(--space-2) var(--space-3);
      background: var(--text-input-background);
      color: var(--ink);
      border: var(--text-input-border);
      border-radius: var(--text-input-radius);
      font-family: var(--font-ui);
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .input.invalid {
      border: var(--text-input-border-error);
    }
    .help {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      line-height: var(--type-caption-line-height);
    }
    .field-error {
      display: flex;
      align-items: flex-start;
      gap: var(--space-1);
      margin: 0;
      color: var(--field-error-foreground);
      font-size: var(--field-error-typography-font-size);
      font-weight: var(--field-error-typography-font-weight);
      line-height: var(--field-error-typography-line-height);
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      align-items: flex-start;
      gap: var(--space-3);
    }
    .saved {
      margin: 0;
      color: var(--ink);
    }
    .check,
    .radio {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      min-height: var(--space-target-min);
    }
    .radios {
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }
    .chip {
      padding: 0 var(--space-2);
      border-radius: var(--citation-chip-radius);
    }
    .chip-unclassified {
      background: var(--classification-unclassified-background);
      color: var(--classification-unclassified-foreground);
    }
    .chip-read-only {
      background: var(--classification-read-only-background);
      color: var(--classification-read-only-foreground);
    }
    .chip-risky {
      background: var(--classification-risky-background);
      color: var(--classification-risky-foreground);
    }
    .selected {
      color: var(--ink);
    }
    .banner {
      display: flex;
      align-items: center;
      gap: var(--space-3);
      box-sizing: border-box;
      width: 100%;
      min-height: var(--status-banner-warning-min-height);
      padding: var(--space-2) var(--space-4);
      border-left: 4px solid var(--status-banner-warning-accent);
      background: var(--status-banner-warning-background);
      color: var(--status-banner-warning-foreground);
      font-size: var(--type-body-font-size);
      font-weight: var(--type-body-font-weight);
      line-height: var(--type-body-line-height);
    }
    .banner .mark {
      flex: none;
      color: var(--status-banner-warning-accent);
    }
    .banner .text {
      flex: 1;
      min-width: 0;
    }
    .load-error {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-3);
    }
    .load-error-text {
      margin: 0;
      color: var(--ink);
    }
  `,
})
export class McpSection {
  private readonly api = inject(ApiClient);
  private readonly announcer = inject(Announcer);
  private readonly dialogs = inject(Dialogs);
  private readonly target = inject(ConfirmRequest);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly destroyed = inject(DestroyRef);

  protected readonly texts = MCP_TEXTS;
  protected readonly denied = SETTINGS_TEXTS.denied;
  protected readonly loadFailed = LOAD_FAILED;
  protected readonly options = CLASSIFICATION_OPTIONS;
  protected readonly intervals = INTERVAL_CHOICES;
  protected readonly saveText = SETTINGS_TEXTS.save;

  /** loading until the list answers; then ready, off (the online demo), denied, or failed (the list did not load). */
  protected readonly state = signal<'loading' | 'ready' | 'off' | 'denied' | 'failed'>('loading');
  protected readonly settings = signal<McpSettings>(NONE);

  protected readonly name = signal('');
  protected readonly address = signal('');
  protected readonly secret = signal('');
  protected readonly nameError = signal('');
  protected readonly addressError = signal('');
  protected readonly secretError = signal('');
  protected readonly addError = signal('');
  protected readonly addDone = signal('');

  /** The tool that the source form is open for, or null while it is closed; its fields, their errors, the form-level error and the line of the last save. */
  protected readonly sourceFor = signal<{ server: string; tool: string } | null>(null);
  protected readonly sourceNameValue = signal('');
  protected readonly sourceArguments = signal('');
  protected readonly sourceInterval = signal(DEFAULT_INTERVAL);
  protected readonly sourceNameError = signal('');
  protected readonly sourceArgumentsError = signal('');
  protected readonly sourceIntervalError = signal('');
  protected readonly sourceError = signal('');
  protected readonly sourceDone = signal('');
  /** The message of the last refused Remove of a source. */
  protected readonly sourcesError = signal('');

  protected readonly onlyUnclassified = signal(false);
  private readonly picked = signal<ReadonlySet<string>>(new Set());
  private readonly rows = signal<Readonly<Record<string, RowState>>>({});
  protected readonly visible = computed(() => visibleTools(this.settings().tools, this.onlyUnclassified(), this.picked()));
  protected readonly changed = computed(() => changedTools(this.settings().tools));

  /** The message of the last refused removal, which the dialog shows. */
  private removeFailed: string = SETTINGS_TEXTS.failed;
  /** The message of the last removal, which is announced once the dialog has closed. */
  private removed = '';

  constructor() {
    this.load();
  }

  /** Retry: asks for the list again; the Observable emits once and completes when the server has answered, whatever the answer. */
  protected readonly retry = (): Observable<void> =>
    new Observable<void>((subscriber) => {
      this.load(() => {
        subscriber.next();
        subscriber.complete();
      });
    });

  /** Loads the list; done is called once the server has answered. */
  private load(done?: () => void): void {
    this.api
      .mcpSettings()
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (list) => {
          this.settings.set(list);
          this.state.set('ready');
          done?.();
        },
        error: (error: unknown) => {
          const state = this.stateOf(error);
          this.state.set(state);
          if (state === 'failed') {
            this.announcer.announce(LOAD_FAILED);
          }
          done?.();
        },
      });
  }

  /** Loads the list again after a change, quietly: a failure keeps what the section shows. */
  private reload(): void {
    this.api
      .mcpSettings()
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (list) => this.settings.set(list),
        error: (error: unknown) => {
          const state = this.stateOf(error);
          if (state !== 'failed') {
            this.state.set(state);
          }
        },
      });
  }

  protected statusOf(status: string): string {
    return statusText(status);
  }

  protected toolStatusOf(status: string): string {
    return toolStatusText(status);
  }

  protected removeNameOf(server: string): string {
    return removeName(server);
  }

  protected groupName(tool: McpToolRow): string {
    return classificationName(tool.name, tool.server);
  }

  protected changedText(tool: McpToolRow): string {
    return toolChangedText(tool.name, tool.server);
  }

  protected key(tool: McpToolRow): string {
    return toolKey(tool.server, tool.name);
  }

  protected sourceable(tool: McpToolRow): boolean {
    return canBeSource(tool);
  }

  protected sourceNameOf(tool: McpToolRow): string {
    return sourceName(tool.name, tool.server);
  }

  protected toolTextOf(tool: string, server: string): string {
    return toolText(tool, server);
  }

  protected removeSourceNameOf(source: McpSourceRow): string {
    return removeSourceName(source);
  }

  protected intervalOf(minutes: number): string {
    return intervalText(minutes);
  }

  protected sourceDescribed(): readonly string[] {
    return this.sourceError() !== '' ? ['mcp-source-error'] : [];
  }

  protected rowState(tool: McpToolRow): RowState {
    return this.rows()[toolKey(tool.server, tool.name)] ?? BLANK;
  }

  protected addDescribed(): readonly string[] {
    return this.addError() !== '' ? ['mcp-add-error'] : [];
  }

  protected toggleOnly(event: Event): void {
    this.onlyUnclassified.set((event.target as HTMLInputElement).checked);
  }

  /** A typed value: clears the field's error, the form error and the line of the last add. */
  protected typed(field: 'name' | 'address' | 'secret', event: Event): void {
    const value = (event.target as HTMLInputElement).value;
    if (field === 'name') {
      this.name.set(value);
      this.nameError.set('');
    } else if (field === 'address') {
      this.address.set(value);
      this.addressError.set('');
    } else {
      this.secret.set(value);
      this.secretError.set('');
    }
    this.addError.set('');
    this.addDone.set('');
  }

  /** Add server: posts the name, the address and the secret; the answer decides what the section shows. */
  protected readonly add = (): Observable<unknown> => {
    this.nameError.set('');
    this.addressError.set('');
    this.secretError.set('');
    this.addError.set('');
    this.addDone.set('');
    return this.api.addMcpServer(addBody(this.name(), this.address(), this.secret())).pipe(
      tap({
        next: (answer) => {
          this.name.set('');
          this.address.set('');
          this.secret.set('');
          this.addDone.set(answer.message);
          this.announcer.announce(answer.message);
          this.reload();
        },
        error: (error: unknown) => this.refusedAdd(error),
      }),
    );
  };

  /** Opens the source form for a Read-only tool: empty fields, 15 minutes, and focus on Source name. A tool that is not Read-only does nothing. */
  protected openSource(tool: McpToolRow): void {
    if (!canBeSource(tool)) {
      return;
    }
    this.clearSource();
    this.sourceDone.set('');
    this.sourceFor.set({ server: tool.server, tool: tool.name });
    this.moveFocusTo('#mcp-source-name');
  }

  /** Closes the form; `back` returns focus to the button that opened it. */
  protected closeSource(back: boolean): void {
    const target = this.sourceFor();
    this.sourceFor.set(null);
    this.clearSource();
    if (back && target !== null) {
      this.moveFocusTo(`[data-source-button][data-key="${CSS.escape(toolKey(target.server, target.tool))}"]`);
    }
  }

  private clearSource(): void {
    this.sourceNameValue.set('');
    this.sourceArguments.set('');
    this.sourceInterval.set(DEFAULT_INTERVAL);
    this.sourceNameError.set('');
    this.sourceArgumentsError.set('');
    this.sourceIntervalError.set('');
    this.sourceError.set('');
  }

  /** A typed or chosen value of the source form: clears the field's error and the form error. */
  protected typedSource(field: 'name' | 'arguments' | 'interval', event: Event): void {
    const value = (event.target as HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement).value;
    if (field === 'name') {
      this.sourceNameValue.set(value);
      this.sourceNameError.set('');
    } else if (field === 'arguments') {
      this.sourceArguments.set(value);
      this.sourceArgumentsError.set('');
    } else {
      this.sourceInterval.set(Number(value));
      this.sourceIntervalError.set('');
    }
    this.sourceError.set('');
  }

  /** Save changes of the source form: posts the entered values; the answer decides what the section shows. */
  protected readonly saveSource = (): Observable<unknown> => {
    const target = this.sourceFor();
    if (target === null) {
      return new Observable<void>((subscriber) => subscriber.complete());
    }
    this.sourceDone.set('');
    this.sourcesError.set('');
    this.sourceNameError.set('');
    this.sourceArgumentsError.set('');
    this.sourceIntervalError.set('');
    this.sourceError.set('');
    return this.api.setMcpSource(sourceBody(target.server, target.tool, this.sourceNameValue(), this.sourceArguments(), this.sourceInterval())).pipe(
      tap({
        next: (answer) => {
          this.sourceDone.set(answer.message);
          this.announcer.announce(answer.message);
          this.closeSource(true);
          this.reload();
        },
        error: (error: unknown) => this.refusedSource(error),
      }),
    );
  };

  /** Remove of a source: no dialog (setting it again undoes it); a 200 announces the server's message and loads the list again, and a failure shows the server's message. */
  protected removeSource(source: McpSourceRow): void {
    this.sourcesError.set('');
    this.sourceDone.set('');
    this.api
      .removeMcpSource(source.ref)
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (answer) => {
          this.announcer.announce(answer.message);
          this.reload();
          this.moveFocusTo('#mcp-sources-heading');
        },
        error: (error: unknown) => {
          const outcome = error instanceof HttpErrorResponse ? sourceOutcome(error.status, error.error) : ({ kind: 'form', message: '' } as const);
          if (outcome.kind === 'denied' || outcome.kind === 'off') {
            this.state.set(outcome.kind);
            return;
          }
          const text = this.messageOf(error);
          this.sourcesError.set(text);
          this.announcer.announce(text);
          this.reload();
        },
      });
  }

  /** Opens the Remove dialog for a server; the button that opened it gets focus back when the dialog closes without removing. */
  protected askRemove(server: string, tools: number, pending: number, event: Event): void {
    const failed = (): string => this.removeFailed;
    this.removeFailed = SETTINGS_TEXTS.failed;
    this.removed = '';
    this.target.content.set({
      question: removeQuestion(server, tools, pending),
      confirm: MCP_TEXTS.removeButton,
      cancel: MCP_TEXTS.cancel,
      get failed(): string {
        return failed();
      },
      act: () =>
        this.api.removeMcpServer(server).pipe(
          tap({
            next: (answer) => (this.removed = answer.message),
            error: (error: unknown) => {
              this.removeFailed = this.messageOf(error);
              this.reload();
            },
          }),
        ),
    });
    const ref = this.dialogs.open(ConfirmDialog, { labelledBy: CONFIRM_TITLE_ID, restoreFocus: event.currentTarget as HTMLElement });
    ref.closed.subscribe((result) => {
      if (result === CONFIRMED) {
        this.gone(server);
      }
    });
  }

  /** The server is gone: it and its tools leave the lists, the list is loaded again, and focus goes to the Servers heading once the dialog has given it back. */
  private gone(server: string): void {
    this.settings.update((one) => ({ servers: one.servers.filter((row) => row.name !== server), tools: one.tools.filter((row) => row.server !== server), sources: one.sources.filter((row) => row.server !== server) }));
    if (this.removed !== '') {
      this.announcer.announce(this.removed);
    }
    this.reload();
    globalThis.setTimeout(() => this.host.nativeElement.querySelector<HTMLElement>('#mcp-servers-heading')?.focus(), 0);
  }

  /** A radiogroup pick: shows the new value at once, saves it, and puts the old value back with the server's message when the save fails. */
  protected pick(tool: McpToolRow, classification: string): void {
    if (tool.classification === classification) {
      return;
    }
    const before = tool.classification;
    const key = toolKey(tool.server, tool.name);
    this.picked.update((all) => new Set([...all, key]));
    this.setRow(key, BLANK);
    this.settings.update((one) => withClassification(one, tool.server, tool.name, classification));
    this.api
      .classifyMcpTool(tool.server, tool.name, classification)
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: () => {
          this.settings.update((one) => withoutChange(one, tool.server, tool.name));
          this.setRow(key, { saved: true, error: '' });
          this.announcer.announce(MCP_TEXTS.saved);
        },
        error: (error: unknown) => {
          this.settings.update((one) => withClassification(one, tool.server, tool.name, before));
          const outcome = error instanceof HttpErrorResponse ? mcpOutcome(error.status, error.error) : ({ kind: 'form', message: '' } as const);
          if (outcome.kind === 'denied' || outcome.kind === 'off') {
            this.state.set(outcome.kind);
            return;
          }
          const text = this.messageOf(error);
          this.setRow(key, { saved: false, error: text });
          this.announcer.announce(text);
        },
      });
  }

  private setRow(key: string, state: RowState): void {
    this.rows.update((all) => ({ ...all, [key]: state }));
  }

  /** The server's own message of a failed call, or the page's failed text when it sent none. */
  private messageOf(error: unknown): string {
    const outcome = error instanceof HttpErrorResponse ? mcpOutcome(error.status, error.error) : undefined;
    return outcome?.kind === 'form' && outcome.message !== '' ? outcome.message : SETTINGS_TEXTS.failed;
  }

  private stateOf(error: unknown): 'off' | 'denied' | 'failed' {
    if (!(error instanceof HttpErrorResponse)) {
      return 'failed';
    }
    const outcome = mcpOutcome(error.status, error.error);
    return outcome.kind === 'off' ? 'off' : outcome.kind === 'denied' ? 'denied' : 'failed';
  }

  private refusedAdd(error: unknown): void {
    const outcome = error instanceof HttpErrorResponse ? mcpOutcome(error.status, error.error) : ({ kind: 'form', message: '' } as const);
    if (outcome.kind === 'denied' || outcome.kind === 'off') {
      this.state.set(outcome.kind);
      return;
    }
    if (outcome.kind === 'fields') {
      this.nameError.set(outcome.name);
      this.addressError.set(outcome.address);
      this.secretError.set(outcome.secret);
      this.announcer.announce([outcome.name, outcome.address, outcome.secret].filter((text) => text !== '').join(' '));
      this.moveFocusTo(outcome.name !== '' ? '#mcp-name' : outcome.address !== '' ? '#mcp-address' : '#mcp-secret');
      return;
    }
    const text = this.messageOf(error);
    this.addError.set(text);
    this.announcer.announce(text);
    this.reload();
  }

  private refusedSource(error: unknown): void {
    const outcome = error instanceof HttpErrorResponse ? sourceOutcome(error.status, error.error) : ({ kind: 'form', message: '' } as const);
    if (outcome.kind === 'denied' || outcome.kind === 'off') {
      this.state.set(outcome.kind);
      return;
    }
    if (outcome.kind === 'fields') {
      this.sourceNameError.set(outcome.name);
      this.sourceArgumentsError.set(outcome.arguments);
      this.sourceIntervalError.set(outcome.intervalMinutes);
      this.sourceError.set(outcome.tool);
      this.announcer.announce([outcome.tool, outcome.name, outcome.arguments, outcome.intervalMinutes].filter((text) => text !== '').join(' '));
      this.moveFocusTo(outcome.name !== '' ? '#mcp-source-name' : outcome.arguments !== '' ? '#mcp-source-arguments' : outcome.intervalMinutes !== '' ? '#mcp-source-interval' : '#mcp-source-name');
      return;
    }
    const text = this.messageOf(error);
    this.sourceError.set(text);
    this.announcer.announce(text);
    this.reload();
  }

  private moveFocusTo(selector: string): void {
    afterNextRender(() => this.host.nativeElement.querySelector<HTMLElement>(selector)?.focus(), { injector: this.injector });
  }
}
