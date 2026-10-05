import { cloudflare } from "@cloudflare/vite-plugin";
import { defineConfig } from "vite";

export default defineConfig({
	plugins: [cloudflare()],
	// Fixed IPv4 address so bin/test-local posts to a known 127.0.0.1:8787; fail
	// rather than silently pick another port if 8787 is taken.
	server: { host: "127.0.0.1", port: 8787, strictPort: true },
});
