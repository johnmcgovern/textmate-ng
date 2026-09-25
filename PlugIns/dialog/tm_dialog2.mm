//
//  client.mm
//  Created by Allan Odgaard on 2007-09-22.
//

#import <Foundation/Foundation.h>
#import "DialogWire.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <unistd.h>

static double const AppVersion = 2.0;

// Connect to the plug-in's socket, the path in DIALOG_PORT_NAME (the plug-in sets
// it). Returns a connected fd, or -1. This used to be a Distributed Objects
// rootProxy; see DialogWire.h for why it is a socket now.
static int connect_to_server ()
{
	char const* path = getenv("DIALOG_PORT_NAME");
	if(!path)
		return -1;

	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if(fd == -1)
		return -1;

	struct sockaddr_un addr = { 0, AF_UNIX };
	if(strlen(path) >= sizeof(addr.sun_path))
	{
		close(fd);
		return -1;
	}
	strcpy(addr.sun_path, path);
	addr.sun_len = SUN_LEN(&addr);

	if(connect(fd, (struct sockaddr*)&addr, sizeof(addr)) == -1)
	{
		close(fd);
		return -1;
	}
	return fd;
}

char const* create_pipe (char const* name)
{
	char* filename;
	asprintf(&filename, "%s/dialog_fifo_%d_%s", getenv("TMPDIR") ?: "/tmp", getpid(), name);
	int res = mkfifo(filename, 0600);   // only this user; the socket already enforces that
	if((res == -1) && (errno != EEXIST))
	{
		perror("Error creating the named pipe");
		exit(EX_OSERR);
   }
	return filename;
}

int open_pipe (char const* name, int oflag)
{
	int fd = open(name, oflag);
	if(fd == -1)
	{
		perror("Error opening the named pipe");
		exit(EX_IOERR);
	}
	return fd;
}

int main (int argc, char const* argv[])
{
	if(argc == 2 && strcmp(argv[1], "--version") == 0)
	{
		fprintf(stderr, "%1$s %2$.1f (" __DATE__ ")\n", getprogname(), AppVersion);
		return EX_OK;
	}

	// If the argument list starts with a switch then assume it’s meant for trunk dialog
	// and pass it off
	if(argc > 1 && *argv[1] == '-')
		execv(getenv("DIALOG_1"), (char* const*)argv);

	@autoreleasepool{
		int serverFd = connect_to_server();
		if(serverFd == -1)
		{
			fprintf(stderr, "error reaching server\n");
			exit(EX_UNAVAILABLE);
		}

		char const* stdinName  = create_pipe("stdin");
		char const* stdoutName = create_pipe("stdout");
		char const* stderrName = create_pipe("stderr");

		NSMutableArray* args = [NSMutableArray array];
		for(size_t i = 0; i < argc; ++i)
			[args addObject:@(argv[i])];

		NSDictionary* dict = @{
			@"stdin":       @(stdinName),
			@"stdout":      @(stdoutName),
			@"stderr":      @(stderrName),
			@"cwd":         @(getcwd(NULL, 0)),
			@"environment": [[NSProcessInfo processInfo] environment],
			@"arguments":   args,
		};

		// One request, then close the write side. The command's output comes back
		// over the fifos named above, not over this socket.
		bool sent = DialogWriteRequest(serverFd, dict);
		close(serverFd);
		if(!sent)
		{
			fprintf(stderr, "error sending request to server\n");
			exit(EX_UNAVAILABLE);
		}

		int inputFd  = open_pipe(stdinName, O_WRONLY);
		int outputFd = open_pipe(stdoutName, O_RDONLY);
		int errorFd = open_pipe(stderrName, O_RDONLY);

		std::map<int, int> fdMap;
		fdMap[STDIN_FILENO] = inputFd;
		fdMap[outputFd]     = STDOUT_FILENO;
		fdMap[errorFd]      = STDERR_FILENO;

		if(isatty(STDIN_FILENO) != 0)
		{
			fdMap.erase(fdMap.find(STDIN_FILENO));
			close(inputFd);
		}

		while(fdMap.size() > 1 || (fdMap.size() == 1 && fdMap.find(STDIN_FILENO) == fdMap.end()))
		{
			fd_set readfds, writefds;
			FD_ZERO(&readfds); FD_ZERO(&writefds);

			int fdCount = 0;
			for(auto const& pair : fdMap)
			{
				FD_SET(pair.first, &readfds);
				fdCount = std::max(fdCount, pair.first + 1);
			}

			int i = select(fdCount, &readfds, &writefds, NULL, NULL);
			if(i == -1)
			{
				perror("Error from select");
				continue;
			}

			std::vector<int> toRemove;
			for(auto const& pair : fdMap)
			{
				if(FD_ISSET(pair.first, &readfds))
				{
					char buf[1024];
					ssize_t len = read(pair.first, buf, sizeof(buf));

					if(len == 0)
							toRemove.push_back(pair.first); // we can’t remove as long as we need the iterator for the ++
					else	write(pair.second, buf, len);
				}
			}

			for(int key : toRemove)
			{
				if(fdMap[key] == inputFd)
					close(inputFd);
				fdMap.erase(key);
			}
		}

		close(outputFd);
		close(errorFd);
		unlink(stdinName);
		unlink(stdoutName);
		unlink(stderrName);
	}

	return EX_OK;
}
