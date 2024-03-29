defmodule JobCenter do
  @moduledoc """
  A simple job management service.
  """
  use GenServer

  @type state() :: %{
          :id => non_neg_integer,
          :queue => Qex.t(tuple),
          :progress => list,
          :done => list,
          :refs => list
        }

  ## Client APIs

  @doc """
  Start the job center server. It takes a keyword list having initial integer
  job `id` and a default jobs in the queue. The argument defaults to an empty
  list.

  ## Examples

        iex> {:ok, pid} = JobCenter.start_link()
        iex> Process.alive?(pid)
        true
  """
  @spec start_link(list) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Add a job `fun` and `time` to do it to the job queue. Return a positive
  integer job number.

  ## Examples

      iex> {:ok, pid} = JobCenter.start_link()
      iex> JobCenter.add_job(pid, fn -> :one end, 2)
      1
      iex> JobCenter.add_job(pid, fn -> :two end, 1)
      2
  """
  @spec add_job(pid, fun, non_neg_integer) :: non_neg_integer
  def add_job(pid, fun, time) do
    GenServer.call(pid, {:add_job, fun, time})
  end

  @doc """
  Used to request for work. If there are jobs in the queue, a tuple
  `{job_number, fun, time}` is returned. If there are no jobs in the queue,
  `no_work` is returned.

  The system is fair, meaning that jobs are handed out in the order they
  are requested and the same job cannot be allocated to more than one worker
  at a time

  ## Examples

      iex> fun1 = fn -> :one end
      iex> fun2 = fn -> :two end
      iex> opts = [id: 3, queue: [{1, fun1, 2}, {2, fun2, 1}]]
      iex> {:ok, pid} = JobCenter.start_link(opts)
      iex> JobCenter.work_wanted(pid)
      {1, fun1, 2}
      iex> JobCenter.work_wanted(pid)
      {2, fun2, 1}
  """
  @spec work_wanted(pid) :: {non_neg_integer, fun, non_neg_integer} | :no_work
  def work_wanted(pid) do
    GenServer.call(pid, :work_wanted)
  end

  @doc """
  Signal that a job has been done. When a worker has completed a job, it
  calls this function to let the server know.

  ## Examples

      iex> fun = fn -> :one end
      iex> {:ok, pid} = JobCenter.start_link([id: 2, queue: [{1, fun, 2}]])
      iex> {id, ^fun, 2} = JobCenter.work_wanted(pid)
      iex> JobCenter.job_done(pid, id)
      :ok
      iex> JobCenter.job_done(pid, :invalid_id)
      :ok
  """
  @spec job_done(pid, non_neg_integer) :: :ok
  def job_done(pid, int) do
    GenServer.cast(pid, {:job_done, int})
  end

  @doc """
  This reports the status of the jobs in the queue and of jobs that are
  in progress and that have been done.

  ## Examples

      iex> {:ok, pid} = JobCenter.start_link()
      iex> JobCenter.statistics(pid)
      %{queue: [], progress: [], done: []}
  """
  @spec statistics(pid()) :: map
  def statistics(pid) do
    GenServer.call(pid, :get_statistics)
  end

  @spec get_queue_list(pid) :: [{non_neg_integer, fun, non_neg_integer}]
  def get_queue_list(pid) do
    GenServer.call(pid, :get_queue_list)
  end

  @spec get_progress_list(pid) :: [{non_neg_integer, fun, non_neg_integer}]
  def get_progress_list(pid) do
    GenServer.call(pid, :get_progress_list)
  end

  @spec get_done_list(pid) :: [{non_neg_integer, fun, non_neg_integer}]
  def get_done_list(pid) do
    GenServer.call(pid, :get_done_list)
  end

  ## Server Callbacks
  @impl true
  @spec init(any) :: {:ok, state()}
  def init(opts) do
    queue = Keyword.get(opts, :queue, [])
    id = Keyword.get(opts, :id, 1)
    init_state = %{id: id, queue: Qex.new(queue), progress: [], done: [], refs: []}
    {:ok, init_state}
  end

  @impl true
  def handle_call({:add_job, fun, time}, _from, %{id: id} = state) do
    new_state =
      state
      |> Map.update!(:id, &(&1 + 1))
      |> Map.update!(:queue, &Qex.push(&1, {id, fun, time}))

    {:reply, id, new_state}
  end

  def handle_call(:get_statistics, _from, state) do
    %{queue: queue, progress: progress, done: done} = state
    new_queue = Enum.to_list(queue)

    reply = %{queue: new_queue, progress: progress, done: done}
    # |> IO.inspect(label: "Reply")

    {:reply, reply, state}
  end

  def handle_call(:work_wanted, {pid, _tag}, state) do
    queue = Map.fetch!(state, :queue)

    case Qex.pop(queue) do
      {:empty, _} ->
        {:reply, :no_work, state}

      {{:value, {id, _, _time} = work}, new_queue} ->
        ref = Process.monitor(pid)

        new_state =
          state
          |> Map.update!(:progress, &[work | &1])
          |> Map.update!(:refs, &[{ref, id, pid} | &1])
          |> Map.replace!(:queue, new_queue)

        {:reply, work, new_state}
    end
  end

  def handle_call(:get_queue_list, _from, %{queue: q} = state) do
    reply = Enum.to_list(q)
    {:reply, reply, state}
  end

  def handle_call(:get_progress_list, _from, %{progress: list} = state) do
    {:reply, list, state}
  end

  def handle_call(:get_done_list, _from, %{done: list} = state) do
    {:reply, list, state}
  end

  @impl true
  def handle_cast({:job_done, int}, %{progress: list, refs: refs} = state) do
    case List.keyfind(list, int, 0) do
      nil ->
        {:noreply, state}

      {^int, _, _time} = work ->
        progress = List.delete(list, work)

        {ref, ^int, _pid} = List.keyfind!(refs, int, 1)
        reference = List.keydelete(refs, int, 1)
        true = Process.demonitor(ref, [:flush])

        new_state =
          state
          |> Map.update!(:progress, fn _elem -> progress end)
          |> Map.update!(:refs, fn _elem -> reference end)
          |> Map.update!(:done, &[work | &1])

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    %{queue: queue, progress: progress, refs: refs} = state

    case List.keyfind(refs, ref, 0) do
      {^ref, id, _pid} ->
        work = List.keyfind!(progress, id, 0)
        new_refs = List.keydelete(refs, ref, 0)
        new_progress = List.keydelete(progress, id, 0)
        new_queue = Qex.push_front(queue, work)

        new_state =
          state
          |> Map.update!(:queue, fn _elem -> new_queue end)
          |> Map.update!(:progress, fn _elem -> new_progress end)
          |> Map.update!(:refs, fn _elem -> new_refs end)

        {:noreply, new_state}

      nil ->
        # We don't give a damn! (NOT our responsibility!)
        {:noreply, state}
    end
  end
end
