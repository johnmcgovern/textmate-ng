#import "AppControllerSupport.h"
#import <io/path.h>
#import <network/tbz.h>
#import <ns/ns.h>
#import <settings/settings.h>
#import <oak/oak.h>

// The marker path, computed the way the original did: once, into a local, from
// path::join(path::temp(), …). path::temp() with no filename is a plain
// confstr(_CS_DARWIN_USER_TEMP_DIR) with no side effects, so recomputing it is
// the same value every time — checked before relying on it, because the same
// function *does* create a file when given one.
static std::string const& session_restore_marker ()
{
	static std::string const res = path::join(path::temp(), "textmate_session_restore");
	return res;
}

@implementation AppControllerSupport

+ (void)setupSettingsPaths
{
	settings_t::set_default_settings_path([[[NSBundle mainBundle] pathForResource:@"Default" ofType:@"tmProperties"] fileSystemRepresentation]);
	settings_t::set_global_settings_path(path::join(path::home(), "Library/Application Support/TextMate/Global.tmProperties"));
}

+ (void)installDefaultBundlesIfNeeded
{
	std::string dest = path::join(path::home(), "Library/Application Support/TextMate/Managed");
	if(!path::exists(dest))
	{
		if(NSString* archive = [[NSBundle mainBundle] pathForResource:@"DefaultBundles" ofType:@"tbz"])
		{
			path::make_dir(dest);

			network::tbz_t tbz(dest);
			if(tbz)
			{
				int fd = open([archive fileSystemRepresentation], O_RDONLY|O_CLOEXEC);
				if(fd != -1)
				{
					char buf[4096];
					ssize_t len;
					while((len = read(fd, buf, sizeof(buf))) > 0)
					{
						if(write(tbz.input_fd(), buf, len) != len)
						{
							os_log_error(OS_LOG_DEFAULT, "Failed writing bytes to tar");
							break;
						}
					}
					close(fd);
				}

				std::string output, error;
				if(!tbz.wait_for_tbz(&output, &error))
					os_log_error(OS_LOG_DEFAULT, "tar: %{public}s%{public}s", output.c_str(), error.c_str());
			}
			else
			{
				os_log_error(OS_LOG_DEFAULT, "Unable to launch tar");
			}
		}
		else
		{
			os_log_error(OS_LOG_DEFAULT, "No ‘DefaultBundles.tbz’ in TextMate.app");
		}
	}
}

+ (NSString*)sessionRestoreMarkerPath
{
	return to_ns(session_restore_marker());
}

+ (BOOL)markerExistsAtPath:(NSString*)path
{
	return path::exists(to_s(path));
}

+ (void)createMarkerAtPath:(NSString*)path
{
	close(open(to_s(path).c_str(), O_CREAT|O_TRUNC|O_WRONLY|O_CLOEXEC));
}

+ (void)removeMarkerAtPath:(NSString*)path
{
	unlink(to_s(path).c_str());
}

@end
