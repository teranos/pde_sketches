module state;

import std.conv : to;
import std.format : format;
import std.string : join, split, strip;

/// The pad drives Processing sketches on the right side. This process speaks
/// ramen's sockets and holds what the pad has set; bin/renderer is a
/// Processing program that draws whatever state it is handed into the frame
/// file, and says `f` each time a frame is in.
enum name = "sketches";

immutable string[4] pages = ["particles", "lines", "startfield", "scene"];
enum scenePage = 3;

/// The middle row, left to right, per page.
immutable string[3][3] paramNames = [
    ["count", "speed", "size"],
    ["count", "speed", "twist"],
    ["stars", "speed", "trail"],
];

/// What the scene's bottom row pages between, and what any of them takes.
immutable string[5] things = ["sky", "ground", "trunks", "lake", "mist"];
immutable string[3] sceneParams = ["hue", "saturation", "scale"];

/// One knob detent moves every locked parameter this far, on 0..1.
enum step = 0.02;

/// One knob detent of time: a day is 96 of them, 15 minutes each.
enum timeStep = 1.0 / 96;

/// One whole day of the scene, in seconds.
enum cycleSeconds = 180.0;

struct State
{
    size_t page;
    double[3][3] value = [[0.4, 0.3, 0.3], [0.3, 0.3, 0.4], [0.5, 0.3, 0.3]];
    bool[3][3] locked;
    uint width, height;

    double time = 0.22; /// of the day, 0..1, from midnight
    size_t thing;
    bool thingLocked;
    double[3][things.length] sceneValue = 0.5;
    bool[3][things.length] sceneLocked;

    /// A locked thing holds the clock.
    bool running() const
    {
        return !thingLocked;
    }

    /// One line, for the state file that carries it across a relaunch.
    string save() const
    {
        string[] f = [page.to!string];
        foreach (p; 0 .. 3)
            foreach (i; 0 .. 3)
                f ~= format("%.4f", value[p][i]);
        foreach (p; 0 .. 3)
            foreach (i; 0 .. 3)
                f ~= locked[p][i] ? "1" : "0";
        f ~= [format("%.6f", time), thing.to!string, thingLocked ? "1" : "0"];
        foreach (t; 0 .. things.length)
            foreach (i; 0 .. 3)
                f ~= format("%.4f", sceneValue[t][i]);
        foreach (t; 0 .. things.length)
            foreach (i; 0 .. 3)
                f ~= sceneLocked[t][i] ? "1" : "0";
        return f.join(" ");
    }

    /// Reads a line from before the scene (19 fields), from when it had
    /// three things (40), and as it is now (52).
    static State load(string line)
    {
        State st;
        auto f = line.strip.split;
        size_t n;
        if (f.length == 40)
            n = 3;
        else if (f.length == 19 + 3 + things.length * 6)
            n = things.length;
        else if (f.length != 19)
            return st;
        try
        {
            st.page = f[0].to!size_t % pages.length;
            foreach (p; 0 .. 3)
                foreach (i; 0 .. 3)
                {
                    st.value[p][i] = f[1 + p * 3 + i].to!double;
                    st.locked[p][i] = f[10 + p * 3 + i] == "1";
                }
            if (n)
            {
                st.time = f[19].to!double;
                st.thing = f[20].to!size_t % things.length;
                st.thingLocked = f[21] == "1";
                foreach (t; 0 .. n)
                    foreach (i; 0 .. 3)
                    {
                        st.sceneValue[t][i] = f[22 + t * 3 + i].to!double;
                        st.sceneLocked[t][i] = f[22 + n * 3 + t * 3 + i] == "1";
                    }
            }
        }
        catch (Exception)
            return State.init;
        return st;
    }

    /// What the renderer is told: the page and what it draws, nothing else.
    string forRenderer() const
    {
        if (page == scenePage)
        {
            string[] f = ["scene", format("%.6f", time), running ? "1" : "0",
                thing.to!string, thingLocked ? "1" : "0"];
            foreach (t; 0 .. things.length)
                foreach (i; 0 .. 3)
                    f ~= format("%.4f", sceneValue[t][i]);
            foreach (t; 0 .. things.length)
                foreach (i; 0 .. 3)
                    f ~= sceneLocked[t][i] ? "1" : "0";
            return f.join(" ");
        }
        return format("state %s %.4f %.4f %.4f %d %d %d", pages[page],
                value[page][0], value[page][1], value[page][2],
                locked[page][0], locked[page][1], locked[page][2]);
    }

    /// The clock, when it runs.
    void advance(double seconds)
    {
        if (running)
            time = wrapDay(time + seconds / cycleSeconds);
    }
}

double wrapDay(double t)
{
    import std.math : floor;

    return t - floor(t);
}

/// What a word did, so the caller knows what to say back.
enum Change
{
    none,
    size,
    page,
    lock,
    value,
    time,
    thing,
    thingLock,
}

size_t middle(string key)
{
    return key == "ML" ? 0 : key == "MC" ? 1 : 2;
}

/// Raw pad edges, not the paged words: `down ML` is the key itself, where
/// `slower` is also what the knob says with BL held.
Change handle(ref State st, string msg)
{
    import std.algorithm : clamp;

    auto w = msg.strip.split;
    if (w.length == 3 && w[0] == "size")
    {
        uint nw, nh;
        try
        {
            nw = w[1].to!uint;
            nh = w[2].to!uint;
        }
        catch (Exception)
            return Change.none;
        if (nw == st.width && nh == st.height)
            return Change.none;
        st.width = nw;
        st.height = nh;
        return Change.size;
    }
    const scene = st.page == scenePage;
    if (w.length == 2 && w[0] == "down")
    {
        switch (w[1])
        {
        // "TL page left"
        case "TL":
            st.page = (st.page + pages.length - 1) % pages.length;
            return Change.page;
        // "TR page right"
        case "TR":
            st.page = (st.page + 1) % pages.length;
            return Change.page;
        // "middle row the three are each a parameter that can be locked"
        case "ML":
        case "MC":
        case "MR":
            const i = middle(w[1]);
            if (!scene)
            {
                st.locked[st.page][i] = !st.locked[st.page][i];
                return Change.lock;
            }
            // "and while locked, middle row lets you select params like we have now"
            if (!st.thingLocked)
                return Change.none;
            st.sceneLocked[st.thing][i] = !st.sceneLocked[st.thing][i];
            return Change.lock;
        case "BL":
        case "BR":
            // The scene's pager, between things, while none is locked.
            if (!scene || st.thingLocked)
                return Change.none;
            st.thing = (st.thing + (w[1] == "BL" ? things.length - 1 : 1)) % things.length;
            return Change.thing;
        // "bottom middle key will unlock you again, let time continue"
        case "BC":
            if (!scene)
                return Change.none;
            st.thingLocked = !st.thingLocked;
            return Change.thingLock;
        default:
            return Change.none;
        }
    }
    if (w.length == 2 && w[0] == "turn")
    {
        const dir = w[1] == "cw" ? 1 : -1;
        if (scene && !st.thingLocked)
        {
            // Nothing locked in the scene: the wheel is time.
            st.time = wrapDay(st.time + dir * timeStep);
            return Change.time;
        }
        // Every locked parameter moves together.
        bool moved;
        foreach (i; 0 .. 3)
        {
            const on = scene ? st.sceneLocked[st.thing][i] : st.locked[st.page][i];
            auto v = scene ? &st.sceneValue[st.thing][i] : &st.value[st.page][i];
            if (on)
            {
                *v = clamp(*v + dir * step, 0.0, 1.0);
                moved = true;
            }
        }
        return moved ? Change.value : Change.none;
    }
    return Change.none;
}

unittest
{
    State st;
    assert(st.handle("down TL") == Change.page && st.page == 3, "TL wraps left to the last page");
    assert(st.handle("down TR") == Change.page && st.page == 0);
    assert(st.handle("down TR") == Change.page && st.page == 1);
    st.page = 0;

    // Nothing locked: the knob moves nothing.
    const before = st.value;
    assert(st.handle("turn cw") == Change.none && st.value == before);

    // ML and MR locked: one detent moves exactly those two, MC stays.
    st.handle("down ML");
    st.handle("down MR");
    st.handle("turn cw");
    assert(st.value[0][0] == before[0][0] + step);
    assert(st.value[0][1] == before[0][1]);
    assert(st.value[0][2] == before[0][2] + step);

    // A lock belongs to its page: page right, the knob moves nothing there.
    st.handle("down TR");
    assert(st.handle("turn cw") == Change.none);
    st.handle("down TL");

    // Unlocking takes a parameter back out of the turn.
    st.handle("down ML");
    st.handle("turn ccw");
    assert(st.value[0][0] == before[0][0] + step);
    assert(st.value[0][2] == before[0][2]);

    // Clamped to 0..1.
    foreach (_; 0 .. 200)
        st.handle("turn cw");
    assert(st.value[0][2] == 1.0);

    // The bottom row is free outside the scene.
    foreach (key; ["BL", "BC", "BR"])
        assert(st.handle("down " ~ key) == Change.none);

    // The paged words are not this source's: they move nothing.
    foreach (word; ["in", "out", "next", "prev", "slower", "pause", "faster", "rerun", "paramPrev", "paramNext"])
        assert(st.handle(word) == Change.none);

    // A state survives the file it is carried in.
    st.time = 0.6;
    st.thing = 2;
    st.sceneLocked[1][2] = true;
    st.sceneValue[2][0] = 0.25;
    const back = State.load(st.save);
    assert(back.page == st.page && back.locked == st.locked);
    assert(back.thing == 2 && back.sceneLocked == st.sceneLocked && back.sceneValue == st.sceneValue);
    assert(back.time - 0.6 < 1e-6 && 0.6 - back.time < 1e-6);
    foreach (p; 0 .. 3)
        foreach (i; 0 .. 3)
            assert(back.value[p][i] - st.value[p][i] < 1e-4 && st.value[p][i] - back.value[p][i] < 1e-4);

    // A line from when the scene had three things keeps them; lake and mist
    // start at their defaults.
    State three;
    three.sceneValue[1][2] = 0.7;
    three.sceneLocked[2][0] = true;
    auto f = three.save.split;
    const forty = (f[0 .. 22] ~ f[22 .. 31] ~ f[37 .. 46]).join(" ");
    const was = State.load(forty);
    assert(was.sceneValue[1][2] == 0.7 && was.sceneLocked[2][0] && !was.sceneLocked[3][0]);
    assert(was.sceneValue[3] == [0.5, 0.5, 0.5] && was.sceneValue[4] == [0.5, 0.5, 0.5]);

    // A line from before the scene still loads, the scene at its defaults.
    const old = State.load("1 0.4 0.3 0.3 0.6 0.6 0.4 0.5 0.3 0.3 0 0 0 1 1 0 0 0 0");
    assert(old.page == 1 && old.value[1][0] == 0.6 && old.locked[1][0] && old.time == State.init.time);
}

unittest
{
    State st;
    st.page = scenePage;

    // Time runs, and the wheel plays with it.
    assert(st.running);
    st.advance(cycleSeconds / 2);
    assert(st.time - 0.72 < 1e-9 && 0.72 - st.time < 1e-9);
    assert(st.handle("turn cw") == Change.time);
    assert(st.time - (0.72 + timeStep) < 1e-9);
    st.time = 0.995;
    st.handle("turn cw");
    assert(st.time < 0.01, "time wraps past midnight");
    st.handle("turn ccw");
    assert(st.time > 0.99, "and back");

    // Unlocked, the middle row is free and the bottom row pages.
    assert(st.handle("down ML") == Change.none);
    assert(st.handle("down BR") == Change.thing && st.thing == 1);
    assert(st.handle("down BL") == Change.thing && st.thing == 0);
    assert(st.handle("down BL") == Change.thing && st.thing == 4 && things[4] == "mist", "BL wraps to the last thing");
    assert(st.handle("down BL") == Change.thing && st.thing == 3 && things[3] == "lake");
    foreach (_; 0 .. 4)
        st.handle("down BR");
    assert(st.thing == 2, "lake, mist, sky, ground, trunks");

    // BC locks onto the thing: time stops, the pager stops.
    assert(st.handle("down BC") == Change.thingLock && st.thingLocked && !st.running);
    const t = st.time;
    st.advance(30);
    assert(st.time == t);
    assert(st.handle("down BR") == Change.none && st.thing == 2);

    // Locked, the middle row selects params and the wheel moves them, not time.
    assert(st.handle("down ML") == Change.lock && st.sceneLocked[2][0]);
    assert(st.handle("down MR") == Change.lock && st.sceneLocked[2][2]);
    assert(st.handle("turn cw") == Change.value);
    assert(st.time == t);
    assert(st.sceneValue[2][0] == 0.5 + step && st.sceneValue[2][1] == 0.5 && st.sceneValue[2][2] == 0.5 + step);
    foreach (other; [0, 1, 3, 4])
        assert(st.sceneValue[other] == [0.5, 0.5, 0.5], "only that thing moves");

    // BC again: time continues, the wheel is time again, values stay.
    assert(st.handle("down BC") == Change.thingLock && st.running);
    assert(st.handle("turn cw") == Change.time);
    assert(st.sceneValue[2][0] == 0.5 + step);
}

/// TL, knob, TR / ML, MC, MR / BL, BC, BR.
string legend(ref const State st)
{
    string[9] f;
    f[0] = "page left";
    f[2] = "page right";
    if (st.page == scenePage && st.thingLocked)
    {
        f[1] = "turn: locked";
        foreach (i; 0 .. 3)
            f[3 + i] = (st.sceneLocked[st.thing][i] ? "unlock " : "lock ") ~ sceneParams[i];
        f[6] = f[8] = "free";
        f[7] = "unlock " ~ things[st.thing];
    }
    else if (st.page == scenePage)
    {
        f[1] = "turn: time";
        f[3] = f[4] = f[5] = "free";
        f[6] = "prev thing";
        f[7] = "lock " ~ things[st.thing];
        f[8] = "next thing";
    }
    else
    {
        f[1] = "turn: locked";
        foreach (i; 0 .. 3)
            f[3 + i] = (st.locked[st.page][i] ? "unlock " : "lock ") ~ paramNames[st.page][i];
        f[6] = f[7] = f[8] = "free";
    }
    return "legend " ~ name ~ " " ~ f[].join("|");
}

/// The toast for a change, or null when it needs none.
string toast(ref const State st, Change c, string msg)
{
    final switch (c)
    {
    case Change.none, Change.size, Change.value, Change.time:
        return null;
    case Change.page:
        return pages[st.page];
    case Change.thing:
        return things[st.thing];
    case Change.thingLock:
        return st.thingLocked ? things[st.thing] ~ " locked, time stopped" : "time running";
    case Change.lock:
        const i = middle(msg.strip.split[1]);
        if (st.page == scenePage)
            return (st.sceneLocked[st.thing][i] ? "locked " : "unlocked ") ~ sceneParams[i];
        return (st.locked[st.page][i] ? "locked " : "unlocked ") ~ paramNames[st.page][i];
    }
}
