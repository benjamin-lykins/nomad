// Copyright (c) HashiCorp, Inc.
// SPDX-License-Identifier: MPL-2.0

package procstats

import (
	"time"

	"github.com/hashicorp/go-set/v3"
	"github.com/hashicorp/nomad/client/lib/cpustats"
	"github.com/hashicorp/nomad/plugins/drivers"
	"github.com/mitchellh/go-ps"
)

var (
	// The statistics the basic executor exposes
	ExecutorBasicMeasuredMemStats = []string{"RSS", "Swap"}
	ExecutorBasicMeasuredCpuStats = []string{"System Mode", "User Mode", "Percent"}
)

// ProcessID is an alias for int; it just helps us identify where PIDs from
// the kernel are being used.
type ProcessID = int

// ProcUsages is a map from PID to the resources that process is consuming.
//
// The pid type is a string because that's how Nomad wants it.
type ProcUsages map[string]*drivers.ResourceUsage

// A ProcessStats is anything (i.e. a task driver) that implements StatProcesses
// for gathering CPU and memory process stats for all processes associated with
// a task.
type ProcessStats interface {
	StatProcesses() ProcUsages
}

// A ProcessList is anything (i.e. a task driver) that implements ListProcesses
// for gathering the list of process IDs associated with a task.
type ProcessList interface {
	ListProcesses() set.Collection[ProcessID]
}

// Aggregate combines a given ProcUsages with the Tracker for the Client.
func Aggregate(systemStats *cpustats.Tracker, procStats ProcUsages) *drivers.TaskResourceUsage {
	ts := time.Now().UTC().UnixNano()
	var (
		systemModeCPU, userModeCPU, percent float64
		totalRSS, totalSwap                 uint64
	)

	for _, pidStat := range procStats {
		systemModeCPU += pidStat.CpuStats.SystemMode
		userModeCPU += pidStat.CpuStats.UserMode
		percent += pidStat.CpuStats.Percent

		totalRSS += pidStat.MemoryStats.RSS
		totalSwap += pidStat.MemoryStats.Swap
	}

	totalCPU := &drivers.CpuStats{
		SystemMode: systemModeCPU,
		UserMode:   userModeCPU,
		Percent:    percent,
		Measured:   ExecutorBasicMeasuredCpuStats,
		TotalTicks: systemStats.TicksConsumed(percent),
	}

	totalMemory := &drivers.MemoryStats{
		RSS:      totalRSS,
		Swap:     totalSwap,
		Measured: ExecutorBasicMeasuredMemStats,
	}

	resourceUsage := drivers.ResourceUsage{
		MemoryStats: totalMemory,
		CpuStats:    totalCPU,
	}
	return &drivers.TaskResourceUsage{
		ResourceUsage: &resourceUsage,
		Timestamp:     ts,
		Pids:          procStats,
	}
}

func list(executorPID int, processes func() ([]ps.Process, error)) set.Collection[ProcessID] {
	processFamily := set.From([]ProcessID{executorPID})

	allPids, err := processes()
	if err != nil {
		return processFamily
	}

	// A mapping of pids to their parent pids. It is used to build the process
	// tree of the executing task
	pidsRemaining := make(map[int]int, len(allPids))
	for _, pid := range allPids {
		pidsRemaining[pid.Pid()] = pid.PPid()
	}

	for {
		// flag to indicate if we have found a match
		foundNewPid := false

		for pid, ppid := range pidsRemaining {
			childPid := processFamily.Contains(ppid)

			// checking if the pid is a child of any of the parents
			if childPid {
				processFamily.Insert(pid)
				delete(pidsRemaining, pid)
				foundNewPid = true
			}
		}

		if !foundNewPid {
			break
		}
	}

	return processFamily
}
