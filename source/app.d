module app;

import state;

import core.time : MonoTime, msecs, seconds;
import std.conv : to;
import std.format : format;
import std.path : buildPath, dirName;
import std.process : environment;
import std.socket : AddressFamily, Socket, SocketType, UnixAddress;
import std.stdio : stderr;
import std.string : join, split, strip;

/// The renderer: a child whose stdin takes lines and whose stdout says `f`.
struct Renderer
{
    import std.process : Pid, pipeProcess, ProcessPipes, Redirect;

    ProcessPipes pipes;
    bool up;

    void start(string path, string framePath)
    {
        pipes = pipeProcess([path, framePath], Redirect.stdin | Redirect.stdout);
        up = true;
    }

    int fd()
    {
        return up ? pipes.stdout.fileno : -1;
    }

    void tell(string line)
    {
        if (!up)
            return;
        try
        {
            pipes.stdin.writeln(line);
            pipes.stdin.flush();
        }
        catch (Exception)
            up = false;
    }

    /// Closing its stdin is how it is told to go.
    void stop()
    {
        import std.process : wait;

        if (!up)
            return;
        try
            pipes.stdin.close();
        catch (Exception)
        {
        }
        wait(pipes.pid);
        up = false;
    }
}

long stamp(string path)
{
    import std.file : exists, timeLastModified;

    return path.exists ? timeLastModified(path).stdTime : 0;
}

void main()
{
    import core.sys.posix.poll : poll, pollfd, POLLHUP, POLLIN;
    import core.sys.posix.unistd : execv, getpid, read;
    import std.file : exists, readText, remove, thisExePath, write;
    import std.string : toStringz;

    const dir = environment.get("XDG_RUNTIME_DIR", "/tmp");
    const framePath = buildPath(dir, name ~ ".frame");
    const wordsPath = buildPath(dir, name ~ ".words.sock");
    const earPath = buildPath(dir, "ramen-right.sock");
    const statePath = buildPath(dir, name ~ ".state");
    const self = thisExePath;
    const rendererPath = buildPath(self.dirName, "renderer");
    const root = self.dirName.dirName;
    const builds = [self, buildPath(root, "bin", "classes", "pages.class"),
        buildPath(root, "textures", "build", "release.wasm"), buildPath(root, "textures", "gen.js")];

    if (wordsPath.exists)
        remove(wordsPath);
    auto words = new Socket(AddressFamily.UNIX, SocketType.DGRAM);
    words.bind(new UnixAddress(wordsPath));
    words.blocking = false;
    auto mouth = new Socket(AddressFamily.UNIX, SocketType.DGRAM);
    mouth.blocking = false;

    void tell(string msg)
    {
        try
            mouth.sendTo(msg, new UnixAddress(earPath));
        catch (Exception e)
            stderr.writeln("ramen: ", e.msg);
    }

    // The cursor a relaunch carries: page, values and locks. The size is
    // ramen's to tell again, which it does on the first announce.
    State st;
    try
        st = State.load(readText(statePath));
    catch (Exception)
    {
    }

    Renderer r;
    r.start(rendererPath, framePath);
    r.tell(st.forRenderer);

    long[] stamps;
    foreach (b; builds)
        stamps ~= stamp(b);
    // When the sketch was built, local, so a relaunch can say which build it is.
    const built = {
        import std.file : timeLastModified;

        const t = timeLastModified(builds[1]);
        return format("%02d:%02d:%02d", t.hour, t.minute, t.second);
    }();
    bool greeted;
    auto lastAnnounce = MonoTime.zero;
    auto lastCheck = MonoTime.currTime;
    ubyte[512] buf;
    ubyte[256] out_;
    string pending; // what the renderer has said of a line not yet whole

    auto lastTick = MonoTime.currTime;
    for (;;)
    {
        const now = MonoTime.currTime;
        st.advance((now - lastTick).total!"usecs" / 1e6);
        lastTick = now;
        if (now - lastAnnounce > 2.seconds)
        {
            tell(format("source %s %s %s %s", name, framePath, wordsPath, getpid()));
            tell(legend(st));
            lastAnnounce = now;
            if (!greeted)
            {
                greeted = true;
                tell("toast " ~ name ~ " built " ~ built);
            }
        }

        // A new build of either half relaunches the whole: the host execs
        // itself, and the renderer it starts is the new one.
        if (now - lastCheck > 1.seconds)
        {
            lastCheck = now;
            bool changed;
            foreach (i, b; builds)
                changed |= stamp(b) != stamps[i];
            if (changed)
            {
                write(statePath, st.save);
                r.stop();
                words.close();
                stderr.writeln("new build: relaunching");
                const argv = [self.toStringz, null];
                execv(argv[0], argv.ptr);
                stderr.writeln("execv failed");
            }
        }

        pollfd[2] fds;
        fds[0] = pollfd(cast(int) words.handle, POLLIN, 0);
        fds[1] = pollfd(r.fd, POLLIN, 0);
        poll(fds.ptr, 2, 200);

        if (fds[0].revents & POLLIN)
        {
            bool tellRenderer, tellLegend, sizeChanged, wipe, snap;
            string said;
            for (;;)
            {
                const got = words.receive(buf[]);
                if (got <= 0)
                    break;
                const msg = (cast(const(char)[]) buf[0 .. got]).idup;
                const c = handle(st, msg);
                if (c == Change.none)
                    continue;
                if (c == Change.size)
                {
                    sizeChanged = true;
                    continue;
                }
                tellRenderer = true;
                wipe |= c == Change.reset;
                snap |= c == Change.snapshot;
                if (c != Change.value && c != Change.time)
                    tellLegend = true;
                if (auto t = toast(st, c, msg))
                    said = t;
            }
            if (sizeChanged)
                r.tell(format("size %s %s", st.width, st.height));
            if (tellRenderer)
            {
                r.tell(st.forRenderer);
                if (wipe)
                    r.tell("reset");
                if (snap)
                    r.tell("snapshot");
                try
                    write(statePath, st.save);
                catch (Exception)
                {
                }
            }
            if (tellLegend)
                tell(legend(st));
            if (said.length)
                tell("toast " ~ name ~ " " ~ said);
        }

        if (fds[1].revents & (POLLIN | POLLHUP))
        {
            const got = read(r.fd, out_.ptr, out_.length);
            if (got > 0)
            {
                const heard = hear(pending, cast(const(char)[]) out_[0 .. got]);
                if (heard.frame)
                    tell("frame " ~ name);
                foreach (path; heard.saved)
                    tell("clip " ~ name ~ " " ~ path);
            }
            else
            {
                // The renderer died: start it again, told everything.
                stderr.writeln("renderer exited; restarting");
                r.stop();
                import core.thread : Thread;

                Thread.sleep(1.seconds);
                r.start(rendererPath, framePath);
                r.tell(st.forRenderer);
                if (st.width)
                    r.tell(format("size %s %s", st.width, st.height));
            }
        }
    }
}
