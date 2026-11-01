/**
 * Unified Spyder Worker entry point.
 * Retains legacy MessageChain routing and MESSAGE_ROOMS state, while adding
 * Chat v2 (@username, contacts, E2EE envelopes, APNs) via separate CHAT_HUB.
 *
 * The existing /health endpoint is intentionally unchanged.
 * This file does NOT migrate or move MessageChain data.
 */
import messageChainWorker, { SpyderMessageRoom } from '../../MessageChain/relay/src/index.mjs';
import chatWorker, { ChatHub } from './chat.mjs';

export { SpyderMessageRoom, ChatHub };

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    // Preserve old health shape for all existing MessageChain consumers.
    if (url.pathname === '/health') {
      return messageChainWorker.fetch(request, env, ctx);
    }
    // Never redirect legacy requests into ChatHub, even if CHAT_HUB is missing.
    if (url.pathname.startsWith('/v1/conversations/')) {
      return messageChainWorker.fetch(request, env, ctx);
    }
    // Chat v2 health lives at a distinct path to avoid changing /health.
    if (request.method === 'GET' && url.pathname === '/chat/health') {
      url.pathname = '/health';
      return chatWorker.fetch(new Request(url, request), env, ctx);
    }
    return chatWorker.fetch(request, env, ctx);
  }
};
