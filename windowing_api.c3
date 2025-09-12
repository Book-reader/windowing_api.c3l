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
	// fn void? init();
	// fn void quit();
	fn Window? create_window(uint width, uint height, String title);
	fn void destroy_window(Window window);
	fn Event? get_event(Window window, Duration timeout = time::sec(0));
	fn PropVal get_prop(Window window, Prop t);
	fn void set_prop(Window window, Prop t, PropVal p);
	fn void start_draw(Window window) @optional;
	fn void end_draw(Window window) @optional;
	fn void clear(Window window, Colour colour) @optional;
	fn void draw_rectangle(Window window, int x, int y, int width, int height, Colour colour, bool fill = true);
	fn bool supports_multiple_windows();
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

enum Prop
{
	HIDDEN,
	MAXIMISED,
	WIDTH,
	HEIGHT,
	TITLE,
	FRAME_DELAY,
	PARENT_WINDOW,
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

fn void set_window_system(WindowSystem window_system)
{
	// if (current_window_system.ptr != null) current_window_system.quit();
	current_window_system = window_system;
	// current_window_system.init()!;
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

fn Event? get_event(Window window, Duration timeout = time::sec(0)) => current_window_system.get_event(window, timeout);
fn void draw_rectangle(Window window, uint x, uint y, uint width, uint height, Colour colour)
{
	current_window_system.draw_rectangle(window, x, y, width, height, colour);
}

fn void set_parent(Window child, Window parent) => current_window_system.set_prop(child, PARENT_WINDOW, {.type = WINDOW, .window = parent});

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

fn void? SDLWindowSystem.init(&self, Allocator alloc = mem)
{
	if (sdl::init(sdl::INIT_EVERYTHING) < 0) return INIT_FAILED?;
	const DEFAULT_WINDOWS_CAPACITY = 3;
	self.windows.init(alloc, DEFAULT_WINDOWS_CAPACITY);
	self.used_windows.init(alloc, DEFAULT_WINDOWS_CAPACITY);
}
fn void SDLWindowSystem.quit(&self)
{
	sdl::quit();
	self.windows.free();
	self.used_windows.free();
}
<* @require self.used_windows[(usz)window] *>
fn SDLWindowSystemWindow* SDLWindowSystem.get(&self, Window window) => &self.windows[(usz)window];

fn bool SDLWindowSystem.supports_multiple_windows(&self) @dynamic => true;
fn PropVal SDLWindowSystem.get_prop(&self, Window window, Prop p) @dynamic => abort();
fn void SDLWindowSystem.set_prop(&self, Window window, Prop p, PropVal v) @dynamic
{
	switch (p)
	{
		case FRAME_DELAY:
			self.get(window).delay_ms = (int)v.as_float();
		case PARENT_WINDOW:
			sdl::setWindowModalFor(self.get(window).window, self.get(v.as_window()).window);
			break;
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
<* @require self.used_windows[(usz)window] *>
fn void SDLWindowSystem.destroy_window(&self, Window window) @dynamic
{
	sdl::destroyRenderer(self.get(window).renderer);
	sdl::destroyWindow(self.get(window).window);
	self.used_windows[(usz)window] = false;
}

fn void SDLWindowSystem.clear(&self, Window window, Colour colour) @dynamic
{
	sdl::setRenderDrawColor(self.get(window).renderer, ...colour);
	sdl::renderClear(self.get(window).renderer);
}

fn void SDLWindowSystem.draw_rectangle(&self, Window window, int x, int y, int width, int height, Colour colour, bool fill = true) @dynamic
{
	sdl::setRenderDrawColor(self.get(window).renderer, ...colour);
	if (fill)
	{
		sdl::renderFillRect(self.get(window).renderer, &&{x, y, width, height});
	}
	else
	{
		sdl::renderDrawRect(self.get(window).renderer, &&{x, y, width, height});
	}
}

fn Event? SDLWindowSystem.get_event(&self, Window window, Duration timeout = time::sec(0)) @dynamic
{
	sdl::Event e;
	if (timeout == time::sec(0))
	{
		if (!sdl::pollEvent(&e)) return NO_EVENT?;
	}
	else
	{
		if (!sdl::waitEventTimeout(&e, (int)(timeout.to_ms() / 1000))) return NO_EVENT?;
	}
	// Maybe a lookup table of transformation functions would be faster?
	switch (e.type)
	{
		case sdl::QUIT:
			return {.type = QUIT};
		case sdl::KEYDOWN:
			// TODO: also handle modifiers in a bitstruct
			if (e.key.windowid == sdl::getWindowID(self.get(window).window))
			{
				return {.type = KEY_DOWN, .key = SDL_KEYCODE_LOOKUP[(int)e.key.keysym.scancode]};
			}
			else
			{
				sdl::pushEvent(&e);
			}
		default:
			// TODO
	}
	return NO_EVENT?;
}

fn void SDLWindowSystem.end_draw(&self, Window window) @dynamic
{
	sdl::renderPresent(self.get(window).renderer);
	sdl::delay(self.get(window).delay_ms);
}

const KeyCode[(int)sdl::NUM_SCANCODES] SDL_KEYCODE_LOOKUP @private = {
	[0..(int)sdl::NUM_SCANCODES] = UNKNOWN,
	[(int)sdl::SCANCODE_UNKNOWN] = UNKNOWN,
	[(int)sdl::SCANCODE_A] = A,
	[(int)sdl::SCANCODE_B] = B,
	[(int)sdl::SCANCODE_C] = C,
	[(int)sdl::SCANCODE_D] = D,
	[(int)sdl::SCANCODE_E] = E,
	[(int)sdl::SCANCODE_F] = F,
	[(int)sdl::SCANCODE_G] = G,
	[(int)sdl::SCANCODE_H] = H,
	[(int)sdl::SCANCODE_I] = I,
	[(int)sdl::SCANCODE_J] = J,
	[(int)sdl::SCANCODE_K] = K,
	[(int)sdl::SCANCODE_L] = L,
	[(int)sdl::SCANCODE_M] = M,
	[(int)sdl::SCANCODE_N] = N,
	[(int)sdl::SCANCODE_O] = O,
	[(int)sdl::SCANCODE_P] = P,
	[(int)sdl::SCANCODE_Q] = Q,
	[(int)sdl::SCANCODE_R] = R,
	[(int)sdl::SCANCODE_S] = S,
	[(int)sdl::SCANCODE_T] = T,
	[(int)sdl::SCANCODE_U] = U,
	[(int)sdl::SCANCODE_V] = V,
	[(int)sdl::SCANCODE_W] = W,
	[(int)sdl::SCANCODE_X] = X,
	[(int)sdl::SCANCODE_Y] = Y,
	[(int)sdl::SCANCODE_Z] = Z,
	[(int)sdl::SCANCODE_1] = NUM_1,
	[(int)sdl::SCANCODE_2] = NUM_2,
	[(int)sdl::SCANCODE_3] = NUM_3,
	[(int)sdl::SCANCODE_4] = NUM_3,
	[(int)sdl::SCANCODE_5] = NUM_5,
	[(int)sdl::SCANCODE_6] = NUM_6,
	[(int)sdl::SCANCODE_7] = NUM_7,
	[(int)sdl::SCANCODE_8] = NUM_8,
	[(int)sdl::SCANCODE_9] = NUM_8,
	[(int)sdl::SCANCODE_0] = NUM_9,
	[(int)sdl::SCANCODE_RETURN] = UNKNOWN,
	[(int)sdl::SCANCODE_ESCAPE] = ESC,
	[(int)sdl::SCANCODE_BACKSPACE] = BS,
	[(int)sdl::SCANCODE_TAB] = UNKNOWN,
	[(int)sdl::SCANCODE_SPACE] = UNKNOWN,
	[(int)sdl::SCANCODE_MINUS] = UNKNOWN,
	[(int)sdl::SCANCODE_EQUALS] = UNKNOWN,
	[(int)sdl::SCANCODE_LEFTBRACKET] = UNKNOWN,
	[(int)sdl::SCANCODE_RIGHTBRACKET] = UNKNOWN,
	[(int)sdl::SCANCODE_BACKSLASH] = UNKNOWN,
	[(int)sdl::SCANCODE_NONUSHASH] = UNKNOWN,
	[(int)sdl::SCANCODE_SEMICOLON] = UNKNOWN,
	[(int)sdl::SCANCODE_APOSTROPHE] = UNKNOWN,
	[(int)sdl::SCANCODE_GRAVE] = UNKNOWN,
	[(int)sdl::SCANCODE_COMMA] = UNKNOWN,
	[(int)sdl::SCANCODE_PERIOD] = UNKNOWN,
	[(int)sdl::SCANCODE_SLASH] = UNKNOWN,
	[(int)sdl::SCANCODE_CAPSLOCK] = UNKNOWN,
	[(int)sdl::SCANCODE_F1] = UNKNOWN,
	[(int)sdl::SCANCODE_F2] = UNKNOWN,
	[(int)sdl::SCANCODE_F3] = UNKNOWN,
	[(int)sdl::SCANCODE_F4] = UNKNOWN,
	[(int)sdl::SCANCODE_F5] = UNKNOWN,
	[(int)sdl::SCANCODE_F6] = UNKNOWN,
	[(int)sdl::SCANCODE_F7] = UNKNOWN,
	[(int)sdl::SCANCODE_F8] = UNKNOWN,
	[(int)sdl::SCANCODE_F9] = UNKNOWN,
	[(int)sdl::SCANCODE_F10] = UNKNOWN,
	[(int)sdl::SCANCODE_F11] = UNKNOWN,
	[(int)sdl::SCANCODE_F12] = UNKNOWN,
	[(int)sdl::SCANCODE_PRINTSCREEN] = UNKNOWN,
	[(int)sdl::SCANCODE_SCROLLLOCK] = UNKNOWN,
	[(int)sdl::SCANCODE_PAUSE] = UNKNOWN,
	[(int)sdl::SCANCODE_INSERT] = UNKNOWN,
	[(int)sdl::SCANCODE_HOME] = UNKNOWN,
	[(int)sdl::SCANCODE_PAGEUP] = UNKNOWN,
	[(int)sdl::SCANCODE_DELETE] = DEL,
	[(int)sdl::SCANCODE_END] = UNKNOWN,
	[(int)sdl::SCANCODE_PAGEDOWN] = UNKNOWN,
	[(int)sdl::SCANCODE_RIGHT] = UNKNOWN,
	[(int)sdl::SCANCODE_LEFT] = UNKNOWN,
	[(int)sdl::SCANCODE_DOWN] = UNKNOWN,
	[(int)sdl::SCANCODE_UP] = UNKNOWN,
	[(int)sdl::SCANCODE_NUMLOCKCLEAR] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_DIVIDE] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_MULTIPLY] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_MINUS] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_PLUS] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_ENTER] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_1] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_2] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_3] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_4] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_5] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_6] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_7] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_8] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_9] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_0] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_PERIOD] = UNKNOWN,
	[(int)sdl::SCANCODE_NONUSBACKSLASH] = UNKNOWN,
	[(int)sdl::SCANCODE_APPLICATION] = UNKNOWN,
	[(int)sdl::SCANCODE_POWER] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_EQUALS] = UNKNOWN,
	[(int)sdl::SCANCODE_F13] = UNKNOWN,
	[(int)sdl::SCANCODE_F14] = UNKNOWN,
	[(int)sdl::SCANCODE_F15] = UNKNOWN,
	[(int)sdl::SCANCODE_F16] = UNKNOWN,
	[(int)sdl::SCANCODE_F17] = UNKNOWN,
	[(int)sdl::SCANCODE_F18] = UNKNOWN,
	[(int)sdl::SCANCODE_F19] = UNKNOWN,
	[(int)sdl::SCANCODE_F20] = UNKNOWN,
	[(int)sdl::SCANCODE_F21] = UNKNOWN,
	[(int)sdl::SCANCODE_F22] = UNKNOWN,
	[(int)sdl::SCANCODE_F23] = UNKNOWN,
	[(int)sdl::SCANCODE_F24] = UNKNOWN,
	[(int)sdl::SCANCODE_EXECUTE] = UNKNOWN,
	[(int)sdl::SCANCODE_HELP] = UNKNOWN,
	[(int)sdl::SCANCODE_MENU] = UNKNOWN,
	[(int)sdl::SCANCODE_SELECT] = UNKNOWN,
	[(int)sdl::SCANCODE_STOP] = UNKNOWN,
	[(int)sdl::SCANCODE_AGAIN] = UNKNOWN,
	[(int)sdl::SCANCODE_UNDO] = UNKNOWN,
	[(int)sdl::SCANCODE_CUT] = UNKNOWN,
	[(int)sdl::SCANCODE_COPY] = UNKNOWN,
	[(int)sdl::SCANCODE_PASTE] = UNKNOWN,
	[(int)sdl::SCANCODE_FIND] = UNKNOWN,
	[(int)sdl::SCANCODE_MUTE] = UNKNOWN,
	[(int)sdl::SCANCODE_VOLUMEUP] = UNKNOWN,
	[(int)sdl::SCANCODE_VOLUMEDOWN] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_COMMA] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_EQUALSAS400] = UNKNOWN,
	[(int)sdl::SCANCODE_INTERNATIONAL1] = UNKNOWN,
	[(int)sdl::SCANCODE_INTERNATIONAL2] = UNKNOWN,
	[(int)sdl::SCANCODE_INTERNATIONAL3] = UNKNOWN,
	[(int)sdl::SCANCODE_INTERNATIONAL4] = UNKNOWN,
	[(int)sdl::SCANCODE_INTERNATIONAL5] = UNKNOWN,
	[(int)sdl::SCANCODE_INTERNATIONAL6] = UNKNOWN,
	[(int)sdl::SCANCODE_INTERNATIONAL7] = UNKNOWN,
	[(int)sdl::SCANCODE_INTERNATIONAL8] = UNKNOWN,
	[(int)sdl::SCANCODE_INTERNATIONAL9] = UNKNOWN,
	[(int)sdl::SCANCODE_LANG1] = UNKNOWN,
	[(int)sdl::SCANCODE_LANG2] = UNKNOWN,
	[(int)sdl::SCANCODE_LANG3] = UNKNOWN,
	[(int)sdl::SCANCODE_LANG4] = UNKNOWN,
	[(int)sdl::SCANCODE_LANG5] = UNKNOWN,
	[(int)sdl::SCANCODE_LANG6] = UNKNOWN,
	[(int)sdl::SCANCODE_LANG7] = UNKNOWN,
	[(int)sdl::SCANCODE_LANG8] = UNKNOWN,
	[(int)sdl::SCANCODE_LANG9] = UNKNOWN,
	[(int)sdl::SCANCODE_ALTERASE] = UNKNOWN,
	[(int)sdl::SCANCODE_SYSREQ] = UNKNOWN,
	[(int)sdl::SCANCODE_CANCEL] = UNKNOWN,
	[(int)sdl::SCANCODE_CLEAR] = UNKNOWN,
	[(int)sdl::SCANCODE_PRIOR] = UNKNOWN,
	[(int)sdl::SCANCODE_RETURN2] = UNKNOWN,
	[(int)sdl::SCANCODE_SEPARATOR] = UNKNOWN,
	[(int)sdl::SCANCODE_OUT] = UNKNOWN,
	[(int)sdl::SCANCODE_OPER] = UNKNOWN,
	[(int)sdl::SCANCODE_CLEARAGAIN] = UNKNOWN,
	[(int)sdl::SCANCODE_CRSEL] = UNKNOWN,
	[(int)sdl::SCANCODE_EXSEL] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_00] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_000] = UNKNOWN,
	[(int)sdl::SCANCODE_THOUSANDSSEPARATOR] = UNKNOWN,
	[(int)sdl::SCANCODE_DECIMALSEPARATOR] = UNKNOWN,
	[(int)sdl::SCANCODE_CURRENCYUNIT] = UNKNOWN,
	[(int)sdl::SCANCODE_CURRENCYSUBUNIT] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_LEFTPAREN] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_RIGHTPAREN] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_LEFTBRACE] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_RIGHTBRACE] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_TAB] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_BACKSPACE] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_A] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_B] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_C] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_D] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_E] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_F] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_XOR] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_POWER] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_PERCENT] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_LESS] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_GREATER] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_AMPERSAND] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_DBLAMPERSAND] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_VERTICALBAR] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_DBLVERTICALBAR] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_COLON] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_HASH] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_SPACE] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_AT] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_EXCLAM] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_MEMSTORE] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_MEMRECALL] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_MEMCLEAR] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_MEMADD] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_MEMSUBTRACT] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_MEMMULTIPLY] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_MEMDIVIDE] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_PLUSMINUS] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_CLEAR] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_CLEARENTRY] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_BINARY] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_OCTAL] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_DECIMAL] = UNKNOWN,
	[(int)sdl::SCANCODE_KP_HEXADECIMAL] = UNKNOWN,
	[(int)sdl::SCANCODE_LCTRL] = UNKNOWN,
	[(int)sdl::SCANCODE_LSHIFT] = UNKNOWN,
	[(int)sdl::SCANCODE_LALT] = UNKNOWN,
	[(int)sdl::SCANCODE_LGUI] = UNKNOWN,
	[(int)sdl::SCANCODE_RCTRL] = UNKNOWN,
	[(int)sdl::SCANCODE_RSHIFT] = UNKNOWN,
	[(int)sdl::SCANCODE_RALT] = UNKNOWN,
	[(int)sdl::SCANCODE_RGUI] = UNKNOWN,
	[(int)sdl::SCANCODE_MODE] = UNKNOWN,
	[(int)sdl::SCANCODE_AUDIONEXT] = UNKNOWN,
	[(int)sdl::SCANCODE_AUDIOPREV] = UNKNOWN,
	[(int)sdl::SCANCODE_AUDIOSTOP] = UNKNOWN,
	[(int)sdl::SCANCODE_AUDIOPLAY] = UNKNOWN,
	[(int)sdl::SCANCODE_AUDIOMUTE] = UNKNOWN,
	[(int)sdl::SCANCODE_MEDIASELECT] = UNKNOWN,
	[(int)sdl::SCANCODE_WWW] = UNKNOWN,
	[(int)sdl::SCANCODE_MAIL] = UNKNOWN,
	[(int)sdl::SCANCODE_CALCULATOR] = UNKNOWN,
	[(int)sdl::SCANCODE_COMPUTER] = UNKNOWN,
	[(int)sdl::SCANCODE_AC_SEARCH] = UNKNOWN,
	[(int)sdl::SCANCODE_AC_HOME] = UNKNOWN,
	[(int)sdl::SCANCODE_AC_BACK] = UNKNOWN,
	[(int)sdl::SCANCODE_AC_FORWARD] = UNKNOWN,
	[(int)sdl::SCANCODE_AC_STOP] = UNKNOWN,
	[(int)sdl::SCANCODE_AC_REFRESH] = UNKNOWN,
	[(int)sdl::SCANCODE_AC_BOOKMARKS] = UNKNOWN,
	[(int)sdl::SCANCODE_BRIGHTNESSDOWN] = UNKNOWN,
	[(int)sdl::SCANCODE_BRIGHTNESSUP] = UNKNOWN,
	[(int)sdl::SCANCODE_DISPLAYSWITCH] = UNKNOWN,
	[(int)sdl::SCANCODE_KBDILLUMTOGGLE] = UNKNOWN,
	[(int)sdl::SCANCODE_KBDILLUMDOWN] = UNKNOWN,
	[(int)sdl::SCANCODE_KBDILLUMUP] = UNKNOWN,
	[(int)sdl::SCANCODE_EJECT] = UNKNOWN,
	[(int)sdl::SCANCODE_SLEEP] = UNKNOWN,
	[(int)sdl::SCANCODE_APP1] = UNKNOWN,
	[(int)sdl::SCANCODE_APP2] = UNKNOWN,
	[(int)sdl::SCANCODE_AUDIOREWIND] = UNKNOWN,
	[(int)sdl::SCANCODE_AUDIOFASTFORWARD] = UNKNOWN,
	[(int)sdl::SCANCODE_SOFTLEFT] = UNKNOWN,
	[(int)sdl::SCANCODE_SOFTRIGHT] = UNKNOWN,
	[(int)sdl::SCANCODE_CALL] = UNKNOWN,
	[(int)sdl::SCANCODE_ENDCALL] = UNKNOWN,
};
