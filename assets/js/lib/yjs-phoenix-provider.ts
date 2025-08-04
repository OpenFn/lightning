/**
 * Yjs Phoenix Provider for Lightning LiveView Integration
 * Simplified version based on y-phoenix-channel
 */

import * as Y from 'yjs';
import * as encoding from 'lib0/encoding';
import * as decoding from 'lib0/decoding';
import * as syncProtocol from 'y-protocols/sync';
import * as awarenessProtocol from 'y-protocols/awareness';
// @ts-ignore - lib0 Observable is deprecated but functional
import { Observable } from 'lib0/observable';

export const messageSync = 0;
export const messageAwareness = 1;
export const messageQueryAwareness = 3;

export interface YjsMessage {
  type: 'sync' | 'awareness' | 'update';
  payload: Uint8Array | object;
  timestamp: number;
  user_id: string;
}

export interface YjsProviderOptions {
  awareness?: awarenessProtocol.Awareness;
  resyncInterval?: number;
  maxBackoffTime?: number;
}

/**
 * Simplified Yjs provider for Phoenix LiveView integration
 * Uses Phoenix hooks instead of direct WebSocket connection
 */
// @ts-ignore - lib0 Observable is deprecated but functional
export class YjsPhoenixProvider extends Observable<any> {
  public doc: Y.Doc;
  public awareness: awarenessProtocol.Awareness;
  public synced = false;
  private hook?: any;
  private resyncInterval: number;
  private resyncTimeoutId?: NodeJS.Timeout | undefined;

  constructor(doc: Y.Doc, hook: any, options: YjsProviderOptions = {}) {
    super();

    this.doc = doc;
    this.hook = hook;
    this.resyncInterval = options.resyncInterval || 30000;
    this.awareness = options.awareness || new awarenessProtocol.Awareness(doc);

    this.setupDocumentHandlers();
    this.setupAwarenessHandlers();
    this.setupResyncInterval();
  }

  private setupDocumentHandlers() {
    this.doc.on('update', this.handleDocUpdate.bind(this));
  }

  private setupAwarenessHandlers() {
    this.awareness.on('update', this.handleAwarenessUpdate.bind(this));
  }

  private setupResyncInterval() {
    if (this.resyncInterval > 0) {
      this.resyncTimeoutId = setInterval(() => {
        this.requestSync();
      }, this.resyncInterval);
    }
  }

  private handleDocUpdate(update: Uint8Array, origin: any) {
    if (origin !== this) {
      this.sendUpdate(update);
    }
  }

  private handleAwarenessUpdate({
    added,
    updated,
    removed,
  }: {
    added: number[];
    updated: number[];
    removed: number[];
  }) {
    const changedClients = added.concat(updated, removed);
    if (changedClients.length > 0) {
      this.sendAwarenessUpdate(changedClients);
    }
  }

  private sendUpdate(update: Uint8Array) {
    if (!this.hook) return;

    const encoder = encoding.createEncoder();
    encoding.writeVarUint(encoder, messageSync);
    syncProtocol.writeUpdate(encoder, update);

    const message: YjsMessage = {
      type: 'sync',
      payload: encoding.toUint8Array(encoder),
      timestamp: Date.now(),
      user_id: this.getUserId(),
    };

    this.hook.pushEvent('yjs_update', message);
  }

  private sendAwarenessUpdate(changedClients: number[]) {
    if (!this.hook) return;

    const encoder = encoding.createEncoder();
    encoding.writeVarUint(encoder, messageAwareness);
    encoding.writeVarUint8Array(
      encoder,
      awarenessProtocol.encodeAwarenessUpdate(this.awareness, changedClients)
    );

    const message: YjsMessage = {
      type: 'awareness',
      payload: encoding.toUint8Array(encoder),
      timestamp: Date.now(),
      user_id: this.getUserId(),
    };

    this.hook.pushEvent('yjs_awareness', message);
  }

  private requestSync() {
    if (!this.hook) return;

    const encoder = encoding.createEncoder();
    encoding.writeVarUint(encoder, messageSync);
    syncProtocol.writeSyncStep1(encoder, this.doc);

    const message: YjsMessage = {
      type: 'sync',
      payload: encoding.toUint8Array(encoder),
      timestamp: Date.now(),
      user_id: this.getUserId(),
    };

    this.hook.pushEvent('sync_request', message);
  }

  public handleMessage(message: YjsMessage) {
    if (message.payload instanceof Uint8Array) {
      this.processYjsMessage(message.payload);
    }
  }

  private processYjsMessage(buf: Uint8Array) {
    const decoder = decoding.createDecoder(buf);
    const encoder = encoding.createEncoder();
    const messageType = decoding.readVarUint(decoder);

    switch (messageType) {
      case messageSync:
        this.handleSyncMessage(decoder, encoder);
        break;
      case messageAwareness:
        this.handleAwarenessMessage(decoder);
        break;
      case messageQueryAwareness:
        this.handleQueryAwarenessMessage(encoder);
        break;
    }

    // Send response if encoder has content
    const response = encoding.toUint8Array(encoder);
    if (response.length > 0) {
      this.sendEncodedMessage(response);
    }
  }

  private handleSyncMessage(
    decoder: decoding.Decoder,
    encoder: encoding.Encoder
  ) {
    encoding.writeVarUint(encoder, messageSync);
    const syncMessageType = syncProtocol.readSyncMessage(
      decoder,
      encoder,
      this.doc,
      this
    );

    if (syncMessageType === syncProtocol.messageYjsSyncStep2 && !this.synced) {
      this.synced = true;
      this.emit('synced', [true]);
    }
  }

  private handleAwarenessMessage(decoder: decoding.Decoder) {
    awarenessProtocol.applyAwarenessUpdate(
      this.awareness,
      decoding.readVarUint8Array(decoder),
      this
    );
  }

  private handleQueryAwarenessMessage(encoder: encoding.Encoder) {
    encoding.writeVarUint(encoder, messageAwareness);
    encoding.writeVarUint8Array(
      encoder,
      awarenessProtocol.encodeAwarenessUpdate(
        this.awareness,
        Array.from(this.awareness.getStates().keys())
      )
    );
  }

  private sendEncodedMessage(payload: Uint8Array) {
    if (!this.hook) return;

    const message: YjsMessage = {
      type: 'sync',
      payload,
      timestamp: Date.now(),
      user_id: this.getUserId(),
    };

    this.hook.pushEvent('yjs_response', message);
  }

  private getUserId(): string {
    // This will be provided by LiveView context
    return this.hook?.el?.dataset?.userId || 'anonymous';
  }

  public connect() {
    // Initial sync request
    this.requestSync();

    // Query awareness
    if (this.hook) {
      const encoder = encoding.createEncoder();
      encoding.writeVarUint(encoder, messageQueryAwareness);

      const message: YjsMessage = {
        type: 'awareness',
        payload: encoding.toUint8Array(encoder),
        timestamp: Date.now(),
        user_id: this.getUserId(),
      };

      this.hook.pushEvent('yjs_query_awareness', message);
    }
  }

  public disconnect() {
    if (this.resyncTimeoutId) {
      clearInterval(this.resyncTimeoutId);
      this.resyncTimeoutId = undefined;
    }

    // Clear awareness state
    awarenessProtocol.removeAwarenessStates(
      this.awareness,
      Array.from(this.awareness.getStates().keys()).filter(
        client => client !== this.doc.clientID
      ),
      this
    );

    this.synced = false;
    this.emit('status', [{ status: 'disconnected' }]);
  }

  public override destroy() {
    this.disconnect();
    this.doc.off('update', this.handleDocUpdate);
    this.awareness.off('update', this.handleAwarenessUpdate);
    super.destroy();
  }
}
