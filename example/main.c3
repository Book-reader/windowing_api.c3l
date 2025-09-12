module main;
import windowing_api;
import std::thread;
import std::time;
import std::io;

alias wapi = module windowing_api;

fn void main()
{
	SDLWindowSystem sdl;
	sdl.init(mem)!!;
	defer sdl.quit();
	wapi::set_window_system(&sdl);
	Window w = wapi::create_window(800, 600, "Hello from C3!")!!;
	defer wapi::destroy_window(w);
	wapi::set_fps(w, 60);

	Window child = wapi::create_window(200, 100, "Child Window")!!;
	defer wapi::destroy_window(child);
	// the delay from this FPS limit adds on to the delay from the other FPS. multiple windows should probably be either put on separate threads or there could be a global FPS as an option instead.
	// wapi::set_fps(child, 60);
	wapi::set_parent(child, w);

	char i = 255;
	uint x = 0;
	uint y = 0;
	while MAIN: (true)
	{
		x++;
		y++;
		defer i--;
		// TODO: some way to wait for an event forever? ig I could check for time::FOREVER
		while (try e = wapi::get_event(w)) switch (e.type)
		{
			case QUIT:
				break MAIN;
			case KEY_DOWN:
				log::info("got key %s", e.key);
				if (e.key == ESC) log::info("press escape over the child window to quit");
			default:
		}
		wapi::@drawing(w; float delta)
		{
			wapi::clear(w, {(char)i, 0, 255 - (char)i, 255});
			wapi::draw_rectangle(w, x, y, 20, 20, {0, 0, 0, 255});
		};

		while (try e = wapi::get_event(child)) switch (e.type)
		{
			case KEY_DOWN:
				log::info("child got key %s", e.key);
				if (e.key == ESC) break MAIN;
			default:
		}

		wapi::@drawing(child; float delta)
		{
			wapi::clear(child, {0, 0, 0, 255});
		};
	}
}

