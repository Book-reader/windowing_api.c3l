module windowing_api;
import std::time;

faultdef INIT_FAILED, CREATION_FAILED, NO_EVENT, UNSUPPORTED_PROP, PROP_APPLY_FAILURE;

/*alias InitFn = fn void?();
alias QuitFn = fn void();
alias WinCreateFn = fn Window?(uint, uint, String);
alias WinDestroyFn = fn void(Window);
alias GetEventFn = fn Event?(Window, Duration);
alias GetWindowPropFn = fn PropVal(Window, Prop);
alias SetWindowPropFn = fn void(Window, Prop, PropVal);
alias StartDrawFn = fn void(Window);
alias EndDrawFn = fn void(Window);
alias ClearFn = fn void(Window, Colour);
alias DrawRectFn = fn void(Window, uint, uint, uint, uint, Colour, bool);*/

interface WindowSystem
{
	// fn void? init();
	// fn void quit();
	fn Window? create_window(uint width, uint height, String title);
	fn void destroy_window(Window window);
	fn Event? get_event(Window window, Duration timeout = time::sec(0));
	fn PropVal? get_window_prop(Window window, Prop t);
	fn void? set_window_prop(Window window, Prop t, PropVal p);
	fn void start_draw(Window window) @optional;
	fn void end_draw(Window window) @optional;
	fn void clear(Window window, Colour colour) @optional;
	fn void draw_rectangle(Window window, int x, int y, int width, int height, Colour colour, bool fill = true);
	fn PropVal get_system_prop(SystemProp p);
	fn any get_native_handle(Window window);
}

WindowSystem current_window_system;
// TODO: cache the methods here
/*InitFn current_initfn;
QuitFn current_quitfn;
WinCreateFn current_wincreatefn;
WinDestroyFn current_windestroyfn;
GetEventFn current_geteventfn;
GetWindowPropFn current_getpropfn;
SetWindowPropFn current_setpropfn;
StartDrawFn current_startdrawfn;
EndDrawFn current_enddrawfn;
ClearFn current_clearfn;
DrawRectFn current_drawrectfn;*/

const WindowCreationFlags DEFAULT_WINDOW_CREATION_FLAGS = {
	.resizable = false,
};

fn void set_window_system(WindowSystem window_system)
{
	current_window_system = window_system;
}

fn Window? create_window(uint width, uint height, String title, WindowCreationFlags flags = DEFAULT_WINDOW_CREATION_FLAGS)
{
	Window win = current_window_system.create_window(width, height, title)!;
	$foreach $member : WindowCreationFlags.membersof:
		set_prop_flag(win, $eval(@str_upper($member.nameof)), $member.get(flags))!;
	$endforeach
	return win;
}

fn void destroy_window(Window window) => current_window_system.destroy_window(window);

macro @drawing(Window window; @body(float delta))
{
	if (&current_window_system.start_draw) current_window_system.start_draw(window);
	@body(0);
	defer if (&current_window_system.end_draw) current_window_system.end_draw(window);
}

fn void clear(Window window, Colour colour)
{
	if (&current_window_system.clear)
	{
		current_window_system.clear(window, colour);
	}
	else
	{
		current_window_system.draw_rectangle(window, 0, 0, get_prop_int(window, WIDTH)!!, get_prop_int(window, HEIGHT)!!, colour);
	}
}

fn void set_fps(Window window, uint fps) => set_prop_float(window, FRAME_DELAY, (float)(fps != 0 ? (1000.0 / fps) : 0.0))!!;

fn Event? get_event(Window window, Duration timeout = time::sec(0)) => current_window_system.get_event(window, timeout);

fn void draw_rectangle(Window window, uint x, uint y, uint width, uint height, Colour colour) => current_window_system.draw_rectangle(window, x, y, width, height, colour);

fn void? set_parent(Window child, Window parent) => set_prop_window(child, PARENT_WINDOW, parent);

fn void? set_fullscreen(Window window, bool fullscreen) => set_prop_flag(window, FULLSCREEN, fullscreen);

fn void? set_maximised(Window window, bool maximised) => set_prop_flag(window, MAXIMISED, maximised);

fn bool? get_fullscreen(Window window) => get_prop_flag(window, FULLSCREEN);

fn bool? get_maximised(Window window) => get_prop_flag(window, MAXIMISED);

fn int[<2>] get_display_size(Window window) => {get_prop_int(window, SCREEN_WIDTH)!!, get_prop_int(window, SCREEN_HEIGHT)!!};

fn int[<2>] get_default_display_size() => {current_window_system.get_system_prop(DEFAULT_SCREEN_WIDTH).as_int(), current_window_system.get_system_prop(DEFAULT_SCREEN_HEIGHT).as_int()};

<* @require prop.type == FLAG *>
fn void? set_prop_flag(Window window, Prop prop, bool val) => current_window_system.set_window_prop(window, prop, {.type = FLAG, .flag = val});

<* @require prop.type == FLAG *>
fn bool? get_prop_flag(Window window, Prop prop) => current_window_system.get_window_prop(window, prop).as_flag();

<* @require prop.type == INT *>
fn void? set_prop_int(Window window, Prop prop, int val) => current_window_system.set_window_prop(window, prop, {.type = INT, .int_ = val});

<* @require prop.type == INT *>
fn int? get_prop_int(Window window, Prop prop) => current_window_system.get_window_prop(window, prop).as_int();

<* @require prop.type == WINDOW *>
fn void? set_prop_window(Window window, Prop prop, Window val) => current_window_system.set_window_prop(window, prop, {.type = WINDOW, .window = val});

<* @require prop.type == WINDOW *>
fn Window? get_prop_window(Window window, Prop prop) => current_window_system.get_window_prop(window, prop).as_window();

<* @require prop.type == FLOAT *>
fn void? set_prop_float(Window window, Prop prop, float val) => current_window_system.set_window_prop(window, prop, {.type = FLOAT, .float_ = val});

<* @require prop.type == FLOAT *>
fn float? get_prop_float(Window window, Prop prop) => current_window_system.get_window_prop(window, prop).as_float();


bitstruct WindowCreationFlags : char
{
	bool resizable;
}

typedef Window = void*;

alias Colour = char[<4>];

enum Prop : char (PropType type)
{
	HIDDEN = FLAG,
	MAXIMISED = FLAG,
	FULLSCREEN = FLAG,
	WIDTH = INT,
	HEIGHT = INT,
	TITLE = STRING,
	FRAME_DELAY = FLOAT,
	PARENT_WINDOW = WINDOW,
	SCREEN_WIDTH = INT,
	SCREEN_HEIGHT = INT,
	RESIZABLE = FLAG,
}
enum SystemProp
{
	SUPPORTS_FULLSCREEN,
	SUPPORTS_MULTIPLE_WINDOWS,
	DEFAULT_SCREEN_WIDTH,
	DEFAULT_SCREEN_HEIGHT,
}
enum PropType : char
{
	FLAG,
	FLOAT,
	INT,
	STRING,
	WINDOW,
}
struct PropVal
{
	union
	{
		bool flag;
		float float_;
		int int_;
		String string;
		Window window;
	}
	PropType type;
}

<*
 @require self.type == INT
*>
fn int PropVal.as_int(&self) => self.int_;
<*
 @require self.type == FLOAT
*>
fn float PropVal.as_float(&self) => self.float_;
<*
 @require self.type == WINDOW
*>
fn Window PropVal.as_window(&self) => self.window;
<*
 @require self.type == FLAG
*>
fn bool PropVal.as_flag(&self) => self.flag;

enum EventType
{
	QUIT,
	KEY_DOWN,
	KEY_UP,
	KEY_PRESS,
	MOUSE_DOWN,
	MOUSE_UP,
	MOUSE_MOVE,
	WINDOW_RESIZE,
}
struct Event
{
	EventType type;
	union
	{
		KeyCode key;
	}
}

// Doesn't correspond to any real key mapping, could probably copy the kernel, sdl, or rgfw ones
enum KeyCode : ushort
{
	UNKNOWN,
	ESC,
	DEL,
	BS,
	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
	NUM_1,
	NUM_2,
	NUM_3,
	NUM_4,
	NUM_5,
	NUM_6,
	NUM_7,
	NUM_8,
	NUM_9,
	NUM_0,
}

