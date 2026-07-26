/*
	The bundle-facing `TextMate` object for command HTML output.

	Injected at document start by OakHTMLOutputView when the command has not set
	disableJavaScriptAPI. Replaces the WebScriptObject bridge that HOJSBridge used
	to hand to the legacy WebView — WKWebView cannot expose a native object to the
	page, so the object lives here in JavaScript and talks to the app over
	webkit.messageHandlers.

	The API contract is the documented one (see the comments in HOJSBridge.mm) and
	is NOT being redesigned: bundles run unmodified.

	  system(cmd, handler)   handler given -> async, returns a command object
	                         handler null  -> synchronous (slice 3; throws for now)
	  log(msg)
	  open(path, options)    options: a line number or a selection-range string
	  busy      (boolean)    status-bar spinner
	  progress  (0-1)        status-bar progress
*/
(function() {
	"use strict";

	function post(command, payload) {
		window.webkit.messageHandlers.textmate.postMessage({ command: command, payload: payload || {} });
	}

	// A running command. Mirrors the properties the old native object exposed, so
	// existing bundle scripts see the same shape.
	function TMCommand(token) {
		this.token        = token;
		this.outputString = "";
		this.errorString  = "";
		this.status       = null;
		this.onreadoutput = null;
		this.onreaderror  = null;
	}

	TMCommand.prototype.cancel = function() { post("systemCtl", { token: this.token, op: "cancel" }); };
	TMCommand.prototype.write  = function(str) { post("systemCtl", { token: this.token, op: "write", data: String(str) }); };
	TMCommand.prototype.close  = function() { post("systemCtl", { token: this.token, op: "close" }); };

	var nextToken = 1;
	var commands  = new Map();

	var TextMate = {
		system: function(cmd, handler) {
			if(typeof handler !== "function") {
				// Synchronous TextMate.system() is still in use by several bundles
				// (Git, Ruby, Subversion, Mercurial). It needs the sync-XHR bridge
				// that lands in slice 3; fail loudly rather than return undefined
				// and have the caller die on `.outputString`.
				throw new Error("TextMate.system(): synchronous form is not available yet in this build — pass a handler to use the asynchronous form.");
			}

			var token   = nextToken++;
			var command = new TMCommand(token);
			commands.set(token, { command: command, handler: handler });
			post("system", { token: token, cmd: String(cmd) });
			return command;
		},

		log: function(str) { post("log", { message: String(str) }); },

		open: function(path, options) {
			post("open", { path: String(path), options: options === undefined || options === null ? null : options });
		},

		// Called by the app; not part of the bundle-facing API.
		_dispatch: function(token, kind, payload) {
			var entry = commands.get(token);
			if(!entry)
				return;

			var command = entry.command;
			if(kind === "out") {
				command.outputString += payload;
				if(typeof command.onreadoutput === "function")
					command.onreadoutput(payload);
			}
			else if(kind === "err") {
				command.errorString += payload;
				if(typeof command.onreaderror === "function")
					command.onreaderror(payload);
			}
			else if(kind === "exit") {
				command.status = payload;
				commands.delete(token);
				if(typeof entry.handler === "function")
					entry.handler(command);
			}
		}
	};

	// busy/progress were native properties with setters; keep them as properties so
	// `TextMate.busy = true` keeps working rather than becoming a silent no-op.
	Object.defineProperty(TextMate, "busy", {
		set: function(flag) { post("busy", { flag: !!flag }); },
		get: function() { return undefined; }
	});

	Object.defineProperty(TextMate, "progress", {
		set: function(value) { post("progress", { value: Number(value) }); },
		get: function() { return undefined; }
	});

	window.TextMate = TextMate;

	// The legacy WebView reported page errors through the undocumented
	// addMessageToConsole: delegate method. WKWebView has no equivalent, so relay
	// them the same way the About window does.
	window.addEventListener("error", function(event) {
		post("log", {
			message:  event.message,
			filename: event.filename,
			lineno:   event.lineno,
			level:    "error"
		});
	});
})();
