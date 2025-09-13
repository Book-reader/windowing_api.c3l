// sdl2 implementation of the windowing API
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
<*
 @require (usz)window != 0
 @require self.used_windows[(usz)window - 1]
*>
macro SDLWindowSystemWindow* SDLWindowSystem.get(&self, Window window) => &self.windows[(usz)window - 1];

fn any SDLWindowSystem.get_native_handle(&self, Window window) @dynamic => self.get(window);

fn PropVal SDLWindowSystem.get_system_prop(&self, SystemProp p) @dynamic
{
	switch (p)
	{
		case SUPPORTS_FULLSCREEN:
		case SUPPORTS_MULTIPLE_WINDOWS:
			return {.type = FLAG, .flag = true};
		case DEFAULT_SCREEN_WIDTH:
		case DEFAULT_SCREEN_HEIGHT:
			sdl::DisplayMode m;
			if (sdl::getCurrentDisplayMode(0, &m) < 0) abort();
			return {.type = INT, .int_ = p == DEFAULT_SCREEN_WIDTH ? m.w : m.h};
	}
}

fn PropVal? SDLWindowSystem.get_window_prop(&self, Window window, Prop p) @dynamic
{
	switch (p)
	{
		case SCREEN_WIDTH:
		case SCREEN_HEIGHT:
			sdl::DisplayMode m;
			if (sdl::getCurrentDisplayMode(sdl::getWindowDisplayIndex(self.get(window).window), &m) < 0) return PROP_APPLY_FAILURE?;
			return {.type = INT, .int_ = p == SCREEN_WIDTH ? m.w : m.h};
		case RESIZABLE:
		default:
			log::warn("Tried to get unsupported prop %s", p);
			return UNSUPPORTED_PROP?;
	}
}

fn void? SDLWindowSystem.set_window_prop(&self, Window window, Prop p, PropVal v) @dynamic
{
	switch (p)
	{
		case FRAME_DELAY:
			self.get(window).delay_ms = (int)v.as_float();
		case PARENT_WINDOW:
			// TODO: proper error handling
			if (sdl::setWindowModalFor(self.get(window).window, (usz)window == 0 ? null : self.get(v.as_window()).window) < 0) return PROP_APPLY_FAILURE?;
		case FULLSCREEN:
			if (sdl::setWindowFullscreen(self.get(window).window, v.as_flag() ? (uint)sdl::WINDOW_FULLSCREEN : 0) < 0) return PROP_APPLY_FAILURE?;
		case MAXIMISED:
			if (sdl::setWindowFullscreen(self.get(window).window, v.as_flag() ? (uint)sdl::WINDOW_FULLSCREEN_DESKTOP : 0) < 0) return PROP_APPLY_FAILURE?;
		case RESIZABLE:
			// TODO: the SDL2 bindings are broken as this returns `void*` instead of `void`. Hopefully doesn't break things but still should be fixed
			// TODO: the SDL2 bindings are also broken in the way that it uses a regular 1 byte bool instead of the 4 byte SDL_bool for these flags, hopefully that doesn't break anything
			log::info("setting window resizable to %s", v.as_flag());
			sdl::setWindowResizable(self.get(window).window, v.as_flag());
		default:
			log::warn("Tried to set unsupported prop %s", p);
			return UNSUPPORTED_PROP?;
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
	return (Window)(idx + 1);
}

<* @require self.used_windows[(usz)window - 1] *>
fn void SDLWindowSystem.destroy_window(&self, Window window) @dynamic
{
	sdl::destroyRenderer(self.get(window).renderer);
	sdl::destroyWindow(self.get(window).window);
	self.used_windows[(usz)window - 1] = false;
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
	if (!(timeout == time::sec(0) ? sdl::pollEvent(&e) : sdl::waitEventTimeout(&e, (int)(timeout.to_ms() / 1000)))) return NO_EVENT?;
	switch (e.type)
	{
		case sdl::QUIT:
			return {.type = QUIT};
		case sdl::KEYDOWN:
			// TODO: also handle modifiers in a bitstruct
			@if_event(self, &e, e.key.windowid, window)
			{
				return {.type = KEY_DOWN, .key = SDL_KEYCODE_LOOKUP[(int)e.key.keysym.scancode]};
			};
		case sdl::WINDOWEVENT:
			@if_event(self, &e, e.window.windowid, window)
			{
				switch (e.window.event)
				{
					case WindowEventID.WINDOWEVENT_RESIZED.ordinal:
						log::info("window resized!");
					default:
						
				}
			};
		default:
			// TODO
	}
	return NO_EVENT?;
}

macro @if_event(SDLWindowSystem* self, sdl::Event* event, uint windowid, Window window; @body()) @private
{
	if (windowid == sdl::getWindowID(self.get(window).window))
	{
		@body();
	}
	else
	{
		// TODO: is this a good system for handling events checked by the wrong window?
		sdl::pushEvent(event);
	}
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

