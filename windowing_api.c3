module windowing_api;
import std::time;

interface Window
{
	fn void? create(uint width, uint height, String title);
	fn void destroy();
	fn Event get_event(Duration timeout = time::sec(0));
	fn PropVal get_prop(Prop t);
	fn void set_prop(Prop t, PropVal p);
	fn void start_draw() @optional;
	fn void end_draw() @optional;
	fn void clear(Colour colour) @optional;
	fn void draw_rectangle(uint x, uint y, uint width, uint height, Colour colour, bool fill = true);
}

alias Colour = char[<4>];

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
	union
	{
		struct key
		{
			KeyCode code;
		}
	}
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

enum KeyCode : ushort
{

}

faultdef CREATION_FAILED;
macro Window? create_window(uint width, uint height, String title)
{
	$if env::LINUX || $feature(WINDOWING_SDL):
		WAPI_SDLWindow window;
	$else
		$error "unimplemented";
	$endif
	window.create(width, height, title)!;
	return &window;
}

fn void destroy_window(Window window) => window.destroy();

macro @drawing(Window window; @body(float delta))
{
	if (&window.start_draw) window.start_draw();
	@body(0);
	defer if (&window.end_draw) window.end_draw();
}

fn void clear(Window window, Colour colour)
{
	if (&window.clear)
	{
		window.clear(colour);
	}
	else
	{
		window.draw_rectangle(0, 0, window.get_prop(WIDTH).as_int(), window.get_prop(HEIGHT).as_int(), colour);
	}
}

fn void set_fps(Window window, uint fps)
{
	window.set_prop(FRAME_DELAY, {.type = FLOAT, .float_ = (float)(fps != 0 ? (1000.0 / fps) : 0.0)});
}

// SDL implementation
module windowing_api @if(env::LINUX || $feature(WINDOWING_SDL));
import sdl;
import std::time;

struct WAPI_SDLWindow (Window)
{
	sdl::Window* window;
	sdl::Renderer* renderer;
	uint delay_ms;
}

fn void init_sdl() @init
{
	if (sdl::init(sdl::INIT_EVERYTHING) < 0) abort("Failed to initialize SDL2");
	// log::info("init sdl!");
}
fn void deinit_sdl() @finalizer
{
	sdl::quit();
	// log::info("quit sdl!");
}

fn PropVal WAPI_SDLWindow.get_prop(&self, Prop p) @dynamic => abort();
fn void WAPI_SDLWindow.set_prop(&self, Prop p, PropVal v) @dynamic
{
	switch (p)
	{
		case FRAME_DELAY:
			self.delay_ms = (int)v.as_float();
		default:
			abort("%s", p);
	}
}
fn void? WAPI_SDLWindow.create(&self, uint width, uint height, String title) @dynamic
{
	self.window = sdl::createWindow(title, 0, 0, width, height, 0);
	if (self.window == null) return CREATION_FAILED?;

	self.renderer = sdl::createRenderer(self.window, -1, (uint)sdl::RENDERER_ACCELERATED);
	if (self.renderer == null) return CREATION_FAILED?;
}
fn void WAPI_SDLWindow.destroy(&self) @dynamic
{
	sdl::destroyRenderer(self.renderer);
	sdl::destroyWindow(self.window);
}

fn void WAPI_SDLWindow.clear(&self, Colour colour) @dynamic
{
	sdl::setRenderDrawColor(self.renderer, ...colour);
	sdl::renderClear(self.renderer);
}

fn void WAPI_SDLWindow.draw_rectangle(&self, uint x, uint y, uint width, uint height, Colour colour, bool fill = true) @dynamic
{
	sdl::setRenderDrawColor(self.renderer, ...colour);
	abort();
}

fn Event WAPI_SDLWindow.get_event(&self, Duration timeout = time::sec(0)) @dynamic
{
	sdl::Event e;
	sdl::waitEventTimeout(&e, (int)(timeout.to_ms() / 1000));
	return {};
}

fn void WAPI_SDLWindow.end_draw(&self) @dynamic
{
	sdl::renderPresent(self.renderer);
	sdl::delay(self.delay_ms);
}
