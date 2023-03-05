defmodule JobCenterTest do
  use ExUnit.Case
  doctest JobCenter

  test "start_link/1 -> start the server" do
    {:ok, pid} = JobCenter.start_link([])
    assert Process.alive?(pid)
  end

  describe "add_job/2" do
    test "add to an empty queue" do
      {:ok, pid} = JobCenter.start_link([])
      fun = fn -> :empty end

      assert JobCenter.add_job(pid, fun) == 1
      assert JobCenter.get_queue_list(pid) == [{1, fun}]
    end

    test "add to queue with one or more element" do
      fun = fn -> :one_or_more end
      queue = [{1, fun}, {2, fun}]
      {:ok, pid} = JobCenter.start_link(id: 3, queue: queue)
      new_queue = [{1, fun}, {2, fun}, {3, fun}]

      assert JobCenter.add_job(pid, fun) == 3
      assert JobCenter.get_queue_list(pid) == new_queue
    end
  end

  describe "work_wanted/1" do
    test "request from empty queue" do
      {:ok, pid} = JobCenter.start_link()

      assert JobCenter.work_wanted(pid) == :no_work
    end

    test "request from a populated queue" do
      fun = fn -> :populated_queue end
      queue = [{1, fun}, {2, fun}]
      progress = Enum.reverse(queue)
      {:ok, pid} = JobCenter.start_link(id: 3, queue: queue)

      assert JobCenter.work_wanted(pid) == {1, fun}
      assert JobCenter.work_wanted(pid) == {2, fun}
      assert JobCenter.get_progress_list(pid) == progress
    end
  end

  describe "job_done/2" do
    test "signal with an invalid job number" do
      {:ok, pid} = JobCenter.start_link()

      assert JobCenter.job_done(pid, 1000) == :ok
      assert JobCenter.job_done(pid, :invalid) == :ok
    end

    test "signal with a valid job number" do
      fun = fn -> :done_invalid_id end
      queue = [{1, fun}, {2, fun}]
      {:ok, pid} = JobCenter.start_link(id: 3, queue: queue)
      {no1, _} = JobCenter.work_wanted(pid)
      {no2, _} = JobCenter.work_wanted(pid)

      assert JobCenter.job_done(pid, no1) == :ok
      assert JobCenter.get_done_list(pid) == [{1, fun}]
      assert JobCenter.job_done(pid, no2) == :ok
      assert JobCenter.get_done_list(pid) == [{2, fun}, {1, fun}]
    end
  end

  describe "statistics/1" do
    test "with initial state" do
      {:ok, pid} = JobCenter.start_link()
      stats = %{queue: [], progress: [], done: []}

      assert JobCenter.statistics(pid) == stats
    end

    test "stats not empty lists" do
      fun = fn -> :stats end
      queue = [{1, fun}, {2, fun}, {3, fun}]
      {:ok, pid} = JobCenter.start_link(id: 4, queue: queue)
      {id1, _} = JobCenter.work_wanted(pid)
      {_id2, _} = JobCenter.work_wanted(pid)
      :ok = JobCenter.job_done(pid, id1)
      stats = %{queue: [{3, fun}], progress: [{2, fun}], done: [{1, fun}]}

      assert JobCenter.statistics(pid) == stats
    end
  end

  describe "monitor workers" do
    ## If a worker dies, jobs it was doing are returned to the queue
    test "one worker dies" do
      fun = fn -> :one_worker end
      queue = for n <- 1..3, do: {n, fun}
      {:ok, pid} = JobCenter.start_link(id: 4, queue: queue)
      worker_pid = spawn(fn -> req3_do1_and_die(pid) end)
      Process.sleep(100)
      %{queue: q1, progress: p1, done: d1} = JobCenter.statistics(pid)
      true = Process.exit(worker_pid, :kill)
      Process.sleep(100)
      %{queue: q2, progress: p2, done: d2} = JobCenter.statistics(pid)

      assert q1 == []
      assert p1 == [{3, fun}, {1, fun}]
      assert d1 == [{2, fun}]
      assert q2 == [{3, fun}, {1, fun}]
      assert p2 == []
      assert d2 == [{2, fun}]
    end

    test "more than one workers die" do
      fun = fn -> :more_worker end
      queue = for n <- 1..9, do: {n, fun}
      {:ok, pid} = JobCenter.start_link(id: 10, queue: queue)
      worker1 = spawn(fn -> req3_do1_and_die(pid) end)
      Process.sleep(100)
      worker2 = spawn(fn -> req3_do1_and_die(pid) end)
      Process.sleep(100)
      worker3 = spawn(fn -> req3_do1_and_die(pid) end)
      Process.sleep(100)
      %{queue: q1, progress: p1, done: d1} = JobCenter.statistics(pid)
      for w_pid <- [worker1, worker2, worker3], do: Process.exit(w_pid, :kill)
      Process.sleep(100)
      %{queue: q2, progress: p2, done: d2} = JobCenter.statistics(pid)
      expected1 = [{9, fun}, {7, fun}, {6, fun}, {4, fun}, {3, fun}, {1, fun}]

      assert q1 == []
      assert p1 == expected1
      assert d1 == [{8, fun}, {5, fun}, {2, fun}]
      assert q2 == expected1
      assert(p2 == [])
      assert d2 == [{8, fun}, {5, fun}, {2, fun}]
    end
  end

  ## Test Helper Functions
  defp req3_do1_and_die(pid) do
    [_, {id2, _fun}, _] = for _n <- 1..3, do: JobCenter.work_wanted(pid)
    JobCenter.job_done(pid, id2)
    Process.sleep(5000)
  end
end
