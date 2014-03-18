export DEPENDENCY_VERSION=CIH-Sprint-1.8
export DEPENDENCY_TAG_LABEL="Clinic-in-Hand Sprint 1.8, released 2/6/2012"

export TAGGING_DIR=`pwd`;
cd $TAGGING_DIR;
for i in `ls -d1 */`;
    do cd $i;
    make update > /dev/null && echo $i" was make updated.";
    sed -i "" "s/export\ DEPENDENCY_VERSION=HEAD/export\ DEPENDENCY_VERSION=$DEPENDENCY_VERSION/g" Makefile 
    git commit -am "Changed makefile to support tag $DEPENDENCY_VERSION";
    git tag -a $DEPENDENCY_VERSION -m "$DEPENDENCY_TAG_LABEL"; 
    git push --tags;
    cd $TAGGING_DIR; 
done;


