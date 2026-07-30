// Copyright IBM Corp. 2015, 2026
// SPDX-License-Identifier: BUSL-1.1

package command

import (
	"fmt"
	"strings"

	"github.com/hashicorp/nomad/api"
	"github.com/posener/complete"
)

type AgentReloadCommand struct {
	Meta
}

func (c *AgentReloadCommand) Help() string {
	helpText := `
Usage: nomad agent reload [options]

  Triggers a reload of the Nomad agent's configuration. This is equivalent to
  sending a SIGHUP to the agent process.

  When ACLs are enabled, this command requires a token with the 'agent:write'
  capability.

General Options:

  ` + generalOptionsUsage(usageOptsDefault|usageOptsNoNamespace)
	return strings.TrimSpace(helpText)
}

func (c *AgentReloadCommand) Synopsis() string {
	return "Reload the Nomad agent's configuration"
}

func (c *AgentReloadCommand) AutocompleteFlags() complete.Flags {
	return c.Meta.AutocompleteFlags(FlagSetClient)
}

func (c *AgentReloadCommand) AutocompleteArgs() complete.Predictor {
	return complete.PredictNothing
}

func (c *AgentReloadCommand) Name() string { return "agent reload" }

func (c *AgentReloadCommand) Run(args []string) int {
	flags := c.Meta.FlagSet(c.Name(), FlagSetClient)
	flags.Usage = func() { c.Ui.Output(c.Help()) }

	if err := flags.Parse(args); err != nil {
		return 1
	}

	// Check that we got no arguments
	args = flags.Args()
	if len(args) > 0 {
		c.Ui.Error(uiMessageNoArguments)
		c.Ui.Error(commandErrorText(c))
		return 1
	}

	// Get the HTTP client
	client, err := c.Meta.Client()
	if err != nil {
		c.Ui.Error(fmt.Sprintf("Error initializing client: %s", err))
		return 1
	}

	if err := client.Agent().Reload(&api.AgentReloadOpts{}, nil); err != nil {
		c.Ui.Error(fmt.Sprintf("Error reloading agent: %s", err))
		return 1
	}
	return 0
}
