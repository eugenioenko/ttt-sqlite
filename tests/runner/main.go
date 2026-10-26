// Command runner runs the Lua unit tests in tests/*_test.lua with gopher-lua,
// the Lua that ttt embeds.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	lua "github.com/yuin/gopher-lua"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: runner REPO_ROOT")
		os.Exit(2)
	}
	root, err := filepath.Abs(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	specs, _ := filepath.Glob(filepath.Join(root, "tests", "*_test.lua"))
	L := lua.NewState()
	defer L.Close()
	L.SetGlobal("readfile", L.NewFunction(func(L *lua.LState) int {
		b, err := os.ReadFile(L.CheckString(1))
		if err != nil {
			L.Push(lua.LNil)
			L.Push(lua.LString(err.Error()))
			return 2
		}
		L.Push(lua.LString(b))
		return 1
	}))
	L.SetGlobal("ROOT", lua.LString(root))
	list := L.NewTable()
	for _, s := range specs {
		list.Append(lua.LString(s))
	}
	L.SetGlobal("SPECS", list)
	if err := L.DoFile(filepath.Join(root, "tests", "harness.lua")); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if lua.LVAsBool(L.GetGlobal("FAILED")) {
		os.Exit(1)
	}
}
