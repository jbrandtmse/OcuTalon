/// Minimal reproduction for the S11 crash: a trivial embedded Python method.
Class Repro.Py Extends %RegisteredObject
{

/// Imports only threading and os, and returns a string.
ClassMethod PyPing() As %String [ Language = python ]
{
	import threading, os
	return "pong thread=%s pid=%d" % (threading.current_thread().name, os.getpid())
}

}
