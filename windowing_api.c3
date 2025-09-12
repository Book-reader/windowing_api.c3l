module windowing_api;
import std::time;

/*alias InitFn = fn void?();
alias QuitFn = fn void();
alias WinCreateFn = fn Window?(uint, uint, String);
alias WinDestroyFn = fn void(Window);
alias GetEventFn = fn Event?(Window, Duration);
alias GetPropFn = fn PropVal(Window, Prop);
alias SetPropFn = fn void(Window, Prop, PropVal);
alias StartDrawFn = fn void(Window);
alias EndDrawFn = fn void(Window);
alias ClearFn = fn void(Window, Colour);
alias DrawRectFn = fn void(Window, uint, uint, uint, uint, Colour, bool);*/
interface WindowSystem
{
	fn void? init();
	fn void quit();
	fn Window? create_window(uint width, uint height, String title);
	fn void destroy_window(Window window);
	fn Event? get_event(Window window, Duration timeout = time::sec(0));
	fn PropVal get_prop(Window window, Prop t);
	fn void set_prop(Window window, Prop t, PropVal p);
	fn void start_draw(Window window) @optional;
	fn void end_draw(Window window) @optional;
	fn void clear(Window window, Colour colour) @optional;
	fn void draw_rectangle(Window window, uint x, uint y, uint width, uint height, Colour colour, bool fill = true);
}

typedef Window = void*;

alias Colour = char[<4>];

WindowSystem current_window_system;
// TODO: cache the methods here
/*InitFn current_initfn;
QuitFn current_quitfn;
WinCreateFn current_wincreatefn;
WinDestroyFn current_windestroyfn;
GetEventFn current_geteventfn;
GetPropFn current_getpropfn;
SetPropFn current_setpropfn;
StartDrawFn current_startdrawfn;
EndDrawFn current_enddrawfn;
ClearFn current_clearfn;
DrawRectFn current_drawrectfn;*/

enum EventType
{
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
/*	union
	{
		struct key
		{
			KeyCode code;
		}
	}*/
}

enum Prop
{
	HIDDEN,
	MAXIMISED,
	WIDTH,
	HEIGHT,
	TITLE,
	FRAME_DELAY,
}
enum PropType : char
{
	FLAG,
	FLOAT,
	INT,
	STRING,
}
struct PropVal
{
	PropType type;
	union
	{
		bool flag;
		float float_;
		int int_;
		String string;
	}
}

<*
 @require self.type == INT
*>
fn int PropVal.as_int(&self) => self.int_;
<*
 @require self.type == FLOAT
*>
fn float PropVal.as_float(&self) => self.float_;

fn void set_window_system(WindowSystem window_system)
{
	current_window_system = window_system;
}

faultdef INIT_FAILED, CREATION_FAILED, NO_EVENT;
fn Window? create_window(uint width, uint height, String title)
{
	return current_window_system.create_window(width, height, title);
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
		current_window_system.draw_rectangle(window, 0, 0, current_window_system.get_prop(window, WIDTH).as_int(), current_window_system.get_prop(window, HEIGHT).as_int(), colour);
	}
}

fn void set_fps(Window window, uint fps)
{
	current_window_system.set_prop(window, FRAME_DELAY, {.type = FLOAT, .float_ = (float)(fps != 0 ? (1000.0 / fps) : 0.0)});
}

// SDL implementation
module windowing_api @if(env::LINUX || $feature(WINDOWING_SDL));
import sdl;
import std::time;
import std::collections::list;

struct SDLWindowSystem (WindowSystem)
{
	List {SDLWindowSystemWindow} windows;
	List {bool} used_windows;
}

struct SDLWindowSystemWindow
{
	sdl::Window* window;
	sdl::Renderer* renderer;
	uint delay_ms;
}

fn void? SDLWindowSystem.init(&self) @dynamic
{
	if (sdl::init(sdl::INIT_EVERYTHING) < 0) return INIT_FAILED?;
	const DEFAULT_WINDOWS_CAPACITY = 3;
	self.windows.init(mem, DEFAULT_WINDOWS_CAPACITY);
	self.used_windows.init(mem, DEFAULT_WINDOWS_CAPACITY);
}
fn void SDLWindowSystem.quit(&self) @dynamic
{
	sdl::quit();
	self.windows.free();
	self.used_windows.free();
}

fn PropVal SDLWindowSystem.get_prop(&self, Window window, Prop p) @dynamic => abort();
fn void SDLWindowSystem.set_prop(&self, Window window, Prop p, PropVal v) @dynamic
{
	switch (p)
	{
		case FRAME_DELAY:
			self.windows[(usz)window].delay_ms = (int)v.as_float();
		default:
			abort("%s", p);
	}
}
fn Window? SDLWindowSystem.create_window(&self, uint width, uint height, String title) @dynamic
{
	SDLWindowSystemWindow w;
	w.window = sdl::createWindow(title, 0, 0, width, height, 0);
	if (w.window == null) return CREATION_FAILED?;

	w.renderer = sdl::createRenderer(w.window, -1, (uint)sdl::RENDERER_ACCELERATED);
	if (w.renderer == null) return CREATION_FAILED?;

	usz idx = 0;
	foreach (used : self.used_windows)
	{
		if (used)
		{
			idx ++;
		}
		else
		{
			break;
		}
	}
	if (idx != self.windows.len())
	{
		self.windows.set(idx, w);
		self.used_windows.set(idx, true);
	}
	else
	{
		self.windows.push(w);
		self.used_windows.push(true);
	}
	return (Window)idx;
}
fn void SDLWindowSystem.destroy_window(&self, Window window) @dynamic
{
	sdl::destroyRenderer(self.windows[(usz)window].renderer);
	sdl::destroyWindow(self.windows[(usz)window].window);
	self.used_windows[(usz)window] = false;
}

fn void SDLWindowSystem.clear(&self, Window window, Colour colour) @dynamic
{
	sdl::setRenderDrawColor(self.windows[(usz)window].renderer, ...colour);
	sdl::renderClear(self.windows[(usz)window].renderer);
}

fn void SDLWindowSystem.draw_rectangle(&self, Window window, uint x, uint y, uint width, uint height, Colour colour, bool fill = true) @dynamic
{
	sdl::setRenderDrawColor(self.windows[(usz)window].renderer, ...colour);
	abort();
}

fn Event? SDLWindowSystem.get_event(&self, Window window, Duration timeout = time::sec(0)) @dynamic
{
	sdl::Event e;
	sdl::waitEventTimeout(&e, (int)(timeout.to_ms() / 1000));
	return {};
}

fn void SDLWindowSystem.end_draw(&self, Window window) @dynamic
{
	sdl::renderPresent(self.windows[(usz)window].renderer);
	sdl::delay(self.windows[(usz)window].delay_ms);
}
