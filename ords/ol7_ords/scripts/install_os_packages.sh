echo "******************************************************************************"
echo "Install OS Packages." `date`
echo "******************************************************************************"
# fontconfig : Added to support OpenJDK inside container.
yum install -y unzip tar gzip freetype fontconfig iputils
yum update -y
rm -Rf /var/cache/yum
