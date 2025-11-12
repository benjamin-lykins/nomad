// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: BUSL-1.1

package command

import (
	"strings"
)

type ConfigReloadCommand struct {
	Meta
}

func (c *ConfigReloadCommand) Help() string {
	helpText := `
Usage: nomad agent reload [options]

  Trigger a Nomad agent configuration reload on the targeted agent.
  This has the same effect as sending SIGHUP to the agent process.

  If ACLs are enabled, the client token must have "agent:write" permissions.

  General Options:

  ` + generalOptionsUsage(usageOptsDefault|usageOptsNoNamespace) + `

`
	return strings.TrimSpace(helpText)
}

func (c *ConfigReloadCommand) Synopsis() string {
	return "Reload agent configuration"
}

func (c *ConfigReloadCommand) Name() string { return "config reload" }

func (c *ConfigReloadCommand) Run(args []string) int {
	flags := c.Meta.FlagSet(c.Name(), FlagSetClient)
	flags.Usage = func() { c.Ui.Output(c.Help()) }
	if err := flags.Parse(args); err != nil {
		c.Ui.Error(err.Error())
		return 1
	}

	client, err := c.Meta.Client()
	if err != nil {
		c.Ui.Error(err.Error())
		return 1
	}

	if err := client.Agent().Reload(); err != nil {
		c.Ui.Error(err.Error())
		return 1
	}

	c.Ui.Output("Reload signaled")
	return 0
}
