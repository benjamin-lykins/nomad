// Copyright IBM Corp. 2015, 2026
// SPDX-License-Identifier: BUSL-1.1

package command

import (
	"testing"

	"github.com/hashicorp/cli"
	"github.com/hashicorp/nomad/ci"
	"github.com/shoenig/test/must"
)

func TestAgentReloadCommand_Implements(t *testing.T) {
	ci.Parallel(t)
	var _ cli.Command = &AgentReloadCommand{}
}

func TestAgentReloadCommand_Run(t *testing.T) {
	ci.Parallel(t)
	srv, _, url := testServer(t, false, nil)
	defer srv.Shutdown()

	ui := cli.NewMockUi()
	cmd := &AgentReloadCommand{Meta: Meta{Ui: ui}}

	code := cmd.Run([]string{"-address=" + url})
	must.Zero(t, code)
}

func TestAgentReloadCommand_Fails(t *testing.T) {
	ci.Parallel(t)
	ui := cli.NewMockUi()
	cmd := &AgentReloadCommand{Meta: Meta{Ui: ui}}

	// Fails on misuse
	code := cmd.Run([]string{"some", "bad", "args"})
	must.One(t, code)

	out := ui.ErrorWriter.String()
	must.StrContains(t, out, commandErrorText(cmd))

	ui.ErrorWriter.Reset()

	// Fails on connection failure
	code = cmd.Run([]string{"-address=nope"})
	must.One(t, code)

	out = ui.ErrorWriter.String()
	must.StrContains(t, out, "Error reloading agent")
}
