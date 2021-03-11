#!/bin/bash

. $(dirname $0)/../../include.rc
. $(dirname $0)/../../volume.rc

cleanup;

REPLICA=2

TEST glusterd
TEST pidof glusterd

TEST $CLI volume create $V0 replica $REPLICA $H0:$B0/${V0}-00 $H0:$B0/${V0}-01 $H0:$B0/${V0}-10 $H0:$B0/${V0}-11
TEST $CLI volume start $V0

TEST $CLI volume set $V0 cluster.background-self-heal-count 0

## Mount FUSE with caching disabled
TEST $GFS -s $H0 --volfile-id $V0 $M0;

function xattr_query_check()
{
    local path=$1
    local xa_name=$2

    local ret=$(getfattr -n $xa_name $path 2>&1 | grep -o "$xa_name: No such attribute" | wc -l)
    echo $ret
}

function set_xattr()
{
    local path=$1
    local xa_name=$2
    local xa_val=$3

    setfattr -n $xa_name -v $xa_val $path
    echo $?
}

function remove_xattr()
{
    local path=$1
    local xa_name=$2

    setfattr -x $xa_name $path
    echo $?
}

f=f00f
pth=$M0/$f

TEST touch $pth

# fetch backend paths
backend_paths=`get_backend_paths $pth`

# convert it into and array
backend_paths_array=($backend_paths)

# setxattr xattr for this file
EXPECT 0 set_xattr $pth "user.name" "test"

# confirm the set on backend
EXPECT 0 xattr_query_check ${backend_paths_array[0]} "user.name"
EXPECT 0 xattr_query_check ${backend_paths_array[1]} "user.name"

brick_path=`echo ${backend_paths_array[0]} | sed -n 's/\(.*\)\/'$f'/\1/p'`
brick_id=`$CLI volume info $V0 | grep "Brick[[:digit:]]" | grep -n $brick_path  | cut -f1 -d:`

# Kill a brick process
TEST kill_brick $V0 $H0 $brick_path

# remove the xattr from the mount point
EXPECT 0 remove_xattr $pth "user.name"

# we killed ${backend_paths[0]} - so expect the xattr to be there
# on the backend there
EXPECT 0 xattr_query_check ${backend_paths_array[0]} "user.name"
EXPECT 1 xattr_query_check ${backend_paths_array[1]} "user.name"

# restart the brick process
TEST $CLI volume start $V0 force

EXPECT_WITHIN $PROCESS_UP_TIMEOUT "Y" glustershd_up_status
EXPECT_WITHIN $CHILD_UP_TIMEOUT "1" afr_child_up_status_in_shd $V0 0
EXPECT_WITHIN $CHILD_UP_TIMEOUT "1" afr_child_up_status_in_shd $V0 1
EXPECT_WITHIN $CHILD_UP_TIMEOUT "1" afr_child_up_status_in_shd $V0 2
EXPECT_WITHIN $CHILD_UP_TIMEOUT "1" afr_child_up_status_in_shd $V0 3

TEST $CLI volume heal $V0

EXPECT_WITHIN $HEAL_TIMEOUT "0" get_pending_heal_count $V0
# check backends - xattr should not be present anywhere
EXPECT 1 xattr_query_check ${backend_paths_array[0]} "user.name"
EXPECT 1 xattr_query_check ${backend_paths_array[1]} "user.name"

cleanup;
