#import "NMSSHSession.h"

#import "libssh2.h"
#import <netdb.h>
#import <sys/socket.h>
#import <arpa/inet.h>

@interface NMSSHSession () {
    int sock;
    LIBSSH2_SESSION *session;
}
@end

@implementation NMSSHSession
@synthesize host, username, connected;

// -----------------------------------------------------------------------------
// PUBLIC CONNECTION API
// -----------------------------------------------------------------------------

+ (id)connectToHost:(NSString *)host withUsername:(NSString *)username {
    NMSSHSession *session = [[NMSSHSession alloc] initWithHost:host
                                                   andUsername:username];
    [session connect];

    return session;
}

- (id)initWithHost:(NSString *)aHost andUsername:(NSString *)aUsername {
    if ((self = [super init])) {
        host = aHost;
        username = aUsername;
        connected = NO;
    }

    return self;
}

- (BOOL)connect {
    // Try to initialize libssh2
    if (libssh2_init(0) != 0) {
        NSLog(@"NMSSH: libssh2 initialization failed");
        return NO;
    }

    // Try to establish a connection to the server
    sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sin;
    sin.sin_family = AF_INET;
    sin.sin_port = htons([[self port] intValue]);
    sin.sin_addr.s_addr = inet_addr([[self hostIPAddress] UTF8String]);
    if (connect(sock, (struct sockaddr*)(&sin), sizeof(struct sockaddr_in)) != 0) {
        NSLog(@"NMSSH: Failed connection to socket");
        return NO;
    }

    // Create a session instance and start it up.
    session = libssh2_session_init();
    if (libssh2_session_handshake(session, sock)) {
        NSLog(@"NMSSH: Failure establishing SSH session");
        return NO;
    }

    // We managed to successfully setup a connection
    connected = YES;
    return [self isConnected];
}

- (void)disconnect {
    if (session) {
        libssh2_session_disconnect(session, "NMSSH: Disconnect");
        libssh2_session_free(session);
        session = nil;
    }

    if (sock) {
        close(sock);
    }

    libssh2_exit();
}

// -----------------------------------------------------------------------------
// PRIVATE HOST NAME HELPERS
// -----------------------------------------------------------------------------

- (NSString *)hostIPAddress {
    NSString *addr = [[host componentsSeparatedByString:@":"] objectAtIndex:0];

    if (![self isIp:addr]) {
        return [self ipFromDomainName:addr];
    }

    return addr;
}

- (BOOL)isIp:(NSString *)address {
    struct in_addr pin;
    int success = inet_aton([address UTF8String], &pin);
    return (success == 1);
}

- (NSString *)ipFromDomainName:(NSString *)address {
    struct hostent *hostEnt = gethostbyname([address UTF8String]);

    if (hostEnt && hostEnt->h_addr_list && hostEnt->h_addr_list[0]) {
        struct in_addr *inAddr = (struct in_addr *)hostEnt->h_addr_list[0];
        return [NSString stringWithFormat:@"%s", inet_ntoa(*inAddr)];
    }

    return @"";
}

- (NSNumber *)port {
    NSArray *hostComponents = [host componentsSeparatedByString:@":"];

    // If no port was defined, use 22 by default
    if ([hostComponents count] == 1) {
        return [NSNumber numberWithInt:22];
    }

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]];

    return [formatter numberFromString:[hostComponents objectAtIndex:1]];
}

@end
