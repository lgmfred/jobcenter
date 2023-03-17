Job center:- A simple job management service 
============================================

![CI](https://github.com/lgmfred/jobcenter/actions/workflows/ci.yml/badge.svg)
![Docs](https://github.com/lgmfred/jobcenter/actions/workflows/docs.yml/badge.svg)

A terrible solution to the **Chapter 22** exercise in Joe's [Programming Erlang (2nd edition)](https://pragprog.com/titles/jaerlang2/programming-erlang-2nd-edition/). _Read the book if you haven't already. It's good!_

## Getting Started

Follow the [Elixir Installation Guide](https://elixir-lang.org/install.html) to install Elixir.

Clone the repository, install dependencies, run tests, ....

```shell
$ git clone https://github.com/lgmfred/jobcenter.git
$ cd jobcenter
$ mix deps.get
$ mix test
$ mix docs
```

Start the IEx shell and the server. Confirm there are no jobs done, in queue, or in progress.

```elixir
iex(1)> {:ok, pid} = JobCenter.start_link()
{:ok, #PID<0.235.0>}
iex(2)> JobCenter.get_queue_list(pid)
[]
iex(3)> JobCenter.get_progress_list(pid)
[]
iex(4)> JobCenter.get_done_list(pid)    
[]
```
Lets add three jobs to queue and check the three lists.

```elixir
iex(5)> JobCenter.add_job(pid, fn -> :one end, 3)
1
iex(6)> JobCenter.add_job(pid, fn -> :two end, 2)
2
iex(7)> JobCenter.add_job(pid, fn -> :three end, 1) 
3
iex(8)> JobCenter.get_queue_list(pid)           
[
  {1, #Function<45.65746770/0 in :erl_eval.expr/5>, 3},
  {2, #Function<45.65746770/0 in :erl_eval.expr/5>, 2},
  {3, #Function<45.65746770/0 in :erl_eval.expr/5>, 1}
]
iex(9)> JobCenter.get_progress_list(pid)        
[]
iex(10)> JobCenter.get_done_list(pid)            
[]
```
How about we request for 2 jobs, and tell the server we're done with one.

```elixir
iex(11)> {id1, fun1} = JobCenter.work_wanted(pid)
{1, #Function<45.65746770/0 in :erl_eval.expr/5>, 3}
iex(12)> {id2, fun2} = JobCenter.work_wanted(pid)
{2, #Function<45.65746770/0 in :erl_eval.expr/5>, 2}
iex(13)> JobCenter.get_progress_list(pid)        
[
  {2, #Function<45.65746770/0 in :erl_eval.expr/5>, 2},
  {1, #Function<45.65746770/0 in :erl_eval.expr/5>, 3}
]
iex(14)> JobCenter.job_done(pid, id1) 
:ok
```
Current state of the server.

```elixir
iex(15)> JobCenter.get_done_list(pid)            
[{1, #Function<45.65746770/0 in :erl_eval.expr/5>, 3}]
iex(16)> JobCenter.get_progress_list(pid)        
[{2, #Function<45.65746770/0 in :erl_eval.expr/5>, 2}]
iex(17)> JobCenter.get_queue_list(pid)
{3, #Function<45.65746770/0 in :erl_eval.expr/5>, 1}
```

## Concepts learned

- Processes 
- GenServers (and how to test them)
- Testing and TDD
- Documentation and Static Analysis (Doctests, Typespecs, ExDoc and Credo)
- CI/CD with GitHub Actions

