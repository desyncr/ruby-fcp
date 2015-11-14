Ruby FCP client library
==

Ruby client library to access [Freenet][2]. Built upon [FCP][3] v2.

Should be ultra fresh cherry, has most functionality except for pluginmessages(wanted to do a seperate api for each
type). Also runs keep alive function and is thread safe, auto reconnects you as well in case of socket failure,
error/state checking should work properly now. Enjoy!

Usage
==

From the command line:

    ruby -Ilib bin/fput -p <some file> -u 'CHK@'

The command above will upload "some file" file to Freenet.

Building documentation
==

Documentation is provided inline and built with [rdoc][1].


  [1]: https://github.com/rdoc/rdoc
  [2]: https://freenetproject.org
  [3]: https://wiki.freenetproject.org/FCP
