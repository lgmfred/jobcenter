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
end
