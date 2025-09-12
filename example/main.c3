module main;
import windowing_api;
import std::thread;
import std::time;
import std::io;

alias wapi = module windowing_api;

fn void main()
{
	Window w = wapi::create_window(800, 600, "Hello from C3!")!!;
	wapi::set_fps(w, 60);

	usz i = 255;
	while (i--)
	{
		// Event e = w.get_event();
		wapi::@drawing(w; float delta)
		{
			wapi::clear(w, {(char)i, (char)i, (char)i, 255});
		};
	}
	wapi::destroy_window(w);
}

