interperterpath="./build/nvx"

i=1
while [ "$i" -le 9 ]; do
    echo "--------------------$i--------------------"
    $interperterpath ./example/example$i.nvx
    i=$((i + 1))
done