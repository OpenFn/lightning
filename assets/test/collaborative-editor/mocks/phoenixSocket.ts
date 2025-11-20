import { createMockPhoenixChannel } from './phoenixChannel';

// Mock Phoenix Socket - must match real Phoenix Socket interface
export const createMockSocket = () => {
  const socket = {
    isConnected: () => true,
    channel: (topic: string) => {
      // Create a new channel instance for each call
      const mockChannel = createMockPhoenixChannel(topic);
      // Set socket reference on the channel
      mockChannel.socket = socket;
      return mockChannel;
    },
    endPointURL: () => 'ws://localhost:4000/socket',
    makeRef: () => 'test-ref-123',
    sendHeartbeat: () => {},
    connect: () => {},
    disconnect: () => {},
    connectionState: () => 'connected',
    onOpen: () => 1,
    onError: () => 2,
    onClose: () => 3,
  };

  return socket;
};
