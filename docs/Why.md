# Why choose Shake?

Shake is a library for writing build systems. Most large projects have a custom-written build system, and developers working on the project are likely to run the build system many times a day, spending a noticable amount of time [waiting for the build system](http://xkcd.com/303/). Why might you pick Shake over alternative tools for writing build systems (e.g. make, Ant, Scons)? 

* Easier and faster for developers running the build system - Shake based build systems run quickly, require little manual intervention and report estimated completion time as they go.
* Easier and faster for developers writing the build system - Shake provides a powerful language for writing build systems, has excellent support for writing large robust build systems, can express many types of build rules and provides profiling information to help speed up builds.

In the rest of this document we explain and justify the above claims, with links to further details. Shake combines [cutting edge research](http://community.haskell.org/~ndm/downloads/paper-shake_before_building-10_sep_2012.pdf) with a [robust industrial-quality implementation](http://hackage.haskell.org/packages/shake/). Shake is in constant use at many large organisations, including [a large investment bank](http://sc.com/), where is was originally developed and has been in use since 2009.

#### Expresses many types of build rule

Build systems run user supplied commands in an order satisfying dependencies. Many of the advantages of Shake are due to being able to express more powerful dependencies than any other build system. These dependency features ensure you can express the build system you want directly, without having to shoehorn your ideas into whatever dependencies your build system provides. In particular, Shake can express both more dependencies (so things rebuild when they should) and more fine-grained dependencies (so things don't rebuild because something nearby changed).

* Shake based build systems can discover additional dependencies after running previous rules, allowing the build system to generate files and then examine them to determine their dependencies, rather than predict the dependencies in advance. Such capabilities are essential when working with generated source files, but often allow builds to be structured more logically.
* Most build systems only allow dependencies between files, but Shake provides user definable dependencies. By default Shake includes support for dependencies on files, the existance of files, environment variables, directory contents and several others, and adding more to your project is easy. In particular you can include dependencies on things like compiler versions or information stored on a remote machine.

#### Build systems run quickly

Developers are likely to spend a long time waiting for their build system, and consequently Shake is designed to be fast.

* The Shake implementation itself is highly optimised, in common with many build tools. In particular, Shake is designed for especially fast execution when nothing has changed -- a common case when developing.
* Shake benefits from powerful dependencies, which can be more accurate and fine-grained, thus ensuring it only builds what is really necessary.
* Shake has excellent support for parallelism, fully utilising multicore machines. Shake also supports additional resource constraints, allowing builds to run with a higher level of parallelism than would otherwise be possible. As an example, you can limit disk-intensive operations (e.g. linking) without restricting CPU-intensive operations (e.g. compiling).
* Shake avoids rebuilding results where the dependencies are rebuilt but do not change, which is particularly useful for generated source files. The impact can reduce certain common patterns from build times of hours to build times of seconds.

#### Build systems run reliably

A build system is responsibe for producing the files that developers are working with, so it is crucial that developers trust the result so they can properly investigate issues without considering build system involvement.

* The powerful dependency system ensures that all dependencies can be expressed, ensuring the build never misses rebuilding something.
* The Shake implementation itself has an extensive test suite, combining several examples projects and over 100 small unit tests (140 at the last count). In addition a random build system generator allows extensive testing to ensure key properties such as sufficient rebuilding and correctness in the presence of errors.
* Shake builds can be run in a special "lint" mode to check global invariants, detecting and reporting problems such as dependency violations before they cause problems.

#### Requires little manual intervention

Most build systems occasionally require manual intervention, typically wiping the existing build and starting again, when the build system developers change something fundamental. Shake eliminates the need for any manual intervention, reducing time wasted by users of the build system.

* The powerful dependencies ensure things that would normally require manual intervention can be tracked. For example, if the C compiler version is tracked as an explicit dependency, then upgrading the C compiler will rebuild all appropriate C files automatically.
* Shake includes a version with each script, which can be changed to automatically force a complete rebuild.

#### Reports estimated completion time

Shake can report estimated completion time, allowing developers to plan their time better.

* Shake provides both predicted completion time (in minutes and seconds) and the percentage completed. All predictions are based on previously recorded execution times for rules and dynamic predictions of machine load, providing reasonable estimations.
* By default, Shake provides methods to display this information in the title bar on Windows, Linux and Mac, and on Windows 7/8 can also display this information as a progress bar in the taskbar.
* The progress information can be easily integrated into continuous integration systems, for example Team City. 

#### Powerful language

Shake is implemented as a Haskell library, and Shake build systems are structured as Haskell programs which make heavy use of the Shake library functions. Shake is a delicate balance, providing access to the full power of Haskell (so build systems are not limited), yet also not requiring any Haskell knowledge (not just for Haskell programmers).

* By building on top of Haskell, Shake build systems benefit from a powerful standardised language. Having a full language available ensures that anything that would be unsuitable to express in a build system can be implemented in normal Haskell and used seamlessly.
* While Shake build systems can use the full power of Haskell, at the other extreme, they can be treated as a powerful version of make with slightly funny syntax. The build system requires no significant Haskell knowledge, and is designed so that most features are accessible by learning the "Shake syntax", without any appreciation of what the underlying Haskell means.

#### Supports large robust systems

Shake build systems can scale to tens of thousands of lines without becoming unweildy.

* Allows structuring of modules and functions for reuse.
* Types ensure you don't rely on dependencies in the wrong place.



Shake does not provide any support for large build systems, relying on a robust and huge language of Haskell.

* Lint checking to do many sanity checks of the build system, catching errors sooner.

#### Provides profiling information

Provides information about the dependencies, dependency graph, what takes most time etc. Allows developers to understand the build system as run, debug anomolies, and figure out how to make things go faster.

* Can see the dependencies, usually grouped by file type.
* Identify the most expensive rule, and the most expensive file to change.
* Analyse the previous build including what built and why.
* Plot information.
* Query language to determine further information.