/**
 * Cloudflare Worker CORS Proxy
 * 
 * Usage:
 * 1. Deploy this to Cloudflare Workers
 * 2. Set your worker route (e.g., yourworker.com/*)
 * 3. Call it with: https://yourworker.com/?url=https://example.com/resource
 * 
 * Or create a custom domain with your Cloudflare account for better URLs
 */

export default {
  async fetch(request) {
    const url = new URL(request.url);
    
    // Get the target URL from query parameter
    const targetUrl = url.searchParams.get('url');
    
    console.log(`Worker received request for: ${targetUrl}`);
    
    if (!targetUrl) {
      return new Response(
        JSON.stringify({ error: 'Missing url parameter. Usage: ?url=https://example.com' }),
        {
          status: 400,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
          },
        }
      );
    }

    // Validate URL format
    let parsedUrl;
    try {
      parsedUrl = new URL(targetUrl);
    } catch (e) {
      return new Response(
        JSON.stringify({ error: 'Invalid URL format' }),
        {
          status: 400,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        }
      );
    }

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS, POST, PUT, DELETE',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          'Access-Control-Max-Age': '86400',
        },
      });
    }

    try {
      // Create new request to target URL
      const fetchRequest = new Request(targetUrl, {
        method: request.method,
        headers: new Headers(request.headers),
        body: request.method !== 'GET' && request.method !== 'HEAD' ? request.body : undefined,
      });

      // Remove host header to avoid issues
      fetchRequest.headers.delete('Host');

      // Fetch from target
      const response = await fetch(fetchRequest);

      // For binary responses (like .gz files), use arrayBuffer to preserve all bytes
      const responseBuffer = await response.arrayBuffer();
      
      const newResponse = new Response(responseBuffer, {
        status: response.status,
        statusText: response.statusText,
        headers: new Headers(response.headers),
      });
      
      // Add CORS headers
      newResponse.headers.set('Access-Control-Allow-Origin', '*');
      newResponse.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS, POST, PUT, DELETE');
      newResponse.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      newResponse.headers.set('Access-Control-Expose-Headers', '*');
      
      // Add cache headers for better performance
      newResponse.headers.set('Cache-Control', 'public, max-age=3600');
      
      return newResponse;
    } catch (error) {
      return new Response(
        JSON.stringify({ error: `Failed to fetch: ${error.message}` }),
        {
          status: 502,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        }
      );
    }
  },
};
