defmodule JobCenter do
  @moduledoc """
  A simple job management service.
  """
  use GenServer

  @type state() :: %{
          :id => non_neg_integer,
          :queue => Qex.t(tuple),
          :progress => list,
          :done => list
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
  Add a job `fun` to the job queue. Return a positive integer job number.

  ## Examples

      iex> {:ok, pid} = JobCenter.start_link()
      iex> JobCenter.add_job(pid, fn -> :one end)
      1
      iex> JobCenter.add_job(pid, fn -> :two end)
      2
  """
  @spec add_job(pid, fun) :: non_neg_integer
  def add_job(pid, fun) do
    GenServer.call(pid, {:add_job, fun})
  end

  @doc """
  Used to request for work. If there are jobs in the queue, a tuple
  `{job_number, fun}` is returned. If there are no jobs in the queue,
  `no_work` is returned.

  The system is fair, meaning that jobs are handed out in the order they
  are requested and the same job cannot be allocated to more than one worker
  at a time

  ## Examples

      iex> fun1 = fn -> :one end
      iex> fun2 = fn -> :two end
      iex> opts = [id: 3, queue: [{1, fun1}, {2, fun2}]]
      iex> {:ok, pid} = JobCenter.start_link(opts)
      iex> JobCenter.add_job(pid, fun1)
      iex> JobCenter.add_job(pid, fun2)
      iex> JobCenter.work_wanted(pid)
      {1, fun1}
      iex> JobCenter.work_wanted(pid)
      {2, fun2}
  """
  @spec work_wanted(pid) :: {non_neg_integer, fun} | :no_work
  def work_wanted(pid) do
    GenServer.call(pid, :work_wanted)
  end

  @doc """
  Signal that a job has been done. When a worker has completed a job, it
  calls this function to let the server know.

  ## Examples

      iex> fun = fn -> :one end
      iex> {:ok, pid} = JobCenter.start_link([id: 2, queue: [{1, fun}]])
      iex> {id, fun} = JobCenter.work_wanted(pid)
      {1, fun}
      iex> JobCenter.job_done(pid, id)
      :ok
      iex> JobCenter.job_done(pid, :invalid_id)
      :ok
  """
  @spec job_done(pid, non_neg_integer) :: :ok
  def job_done(pid, int) do
    GenServer.cast(pid, {:job_done, int})
  end

  @spec get_queue_list(pid) :: [tuple]
  def get_queue_list(pid) do
    GenServer.call(pid, :get_queue_list)
  end

  @spec get_progress_list(pid) :: [tuple]
  def get_progress_list(pid) do
    GenServer.call(pid, :get_progress_list)
  end

  @spec get_done_list(pid) :: [tuple]
  def get_done_list(pid) do
    GenServer.call(pid, :get_done_list)
  end

  ## Server Callbacks
  @impl true
  @spec init(any) :: {:ok, state()}
  def init(opts) do
    queue = Keyword.get(opts, :queue, [])
    id = Keyword.get(opts, :id, 1)
    init_state = %{id: id, queue: Qex.new(queue), progress: [], done: []}
    {:ok, init_state}
  end

  @impl true
  def handle_call({:add_job, fun}, _from, %{id: id} = state) do
    new_state =
      Map.update!(state, :id, &(&1 + 1))
      |> Map.update!(:queue, &Qex.push(&1, {id, fun}))

    {:reply, id, new_state}
  end

  def handle_call(:work_wanted, _from, state) do
    queue = Map.fetch!(state, :queue)

    case Qex.pop(queue) do
      {:empty, _} ->
        {:reply, :no_work, state}

      {{:value, work}, new_queue} ->
        new_state =
          Map.update!(state, :progress, &[work | &1])
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
  def handle_cast({:job_done, int}, %{progress: list} = state) do
    case List.keyfind(list, int, 0) do
      nil ->
        {:noreply, state}

      {_int, _} = work ->
        progress = List.delete(list, work)

        new_state =
          Map.update!(state, :progress, fn _elem -> progress end)
          |> Map.update!(:done, &[work | &1])

        {:noreply, new_state}
    end
  end
end
