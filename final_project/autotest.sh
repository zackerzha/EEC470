#!/bin/bash
current_directory=$(pwd)
result_file=test_result.out

cd $current_directory/test_progs
filec=*.c
echo "@@@ Test for *.c" >> $result_file
for file1 in $filec; do
    cd $current_directory
    #make clean
    make program SOURCE=test_progs/${file1}
    make syn > program.out
    filename1=$(echo $file1 | cut -d '.' -f1) 
    WB_CHECK=$(diff  ${current_directory}/writeback.out wb_dir_c/${filename1}/writeback.out)
    DIFF_PROG=$(diff <(grep '@@@' ${current_directory}/program.out) <(grep '@@@' wb_dir_c/${filename1}/program.out))
    if  [ "$WB_CHECK" != "" ] | [ "$DIFF_PROG" != "" ]
    then
        echo "Test failed for ${file1}" >> $result_file
        result_flag=`expr ${result_flag} + 1 `
    else
        echo "Test passed for ${file1}" >> $result_file
    fi
done

if [ "$result_flag" == 0 ]
then
    echo "@@@ All Test Has Passed!"
    echo "@@@ All Test Has Passed!" >> $result_file
else
    echo "@@@ $result_flag Test Has Failed!"
    echo "@@@ $result_flag Test Has Failed!" >> $result_file
fi