#!/bin/sh
# Parallels 9 + Kali Linux 1.0.6 (kernel 3.12)
#

# Prepare environment
apt-get update && apt-get install -y gcc dkms make linux-headers-$(uname -r)

#cp -R /media/$USER/Parallels\ Tools /tmp/
cp -R /media/cdrom0 /tmp/
# cd /tmp/Parallels\ Tools/kmods
cd /tmp/cdrom0/kmods

# Patch
tee /tmp/parallels-tools-linux-3.12-prl-fs-9.0.23350.941886.patch <<EOF
diff -Nru prl_fs.orig/SharedFolders/Guest/Linux/prl_fs/inode.c prl_fs/SharedFolders/Guest/Linux/prl_fs/inode.c
--- prl_fs.orig/SharedFolders/Guest/Linux/prl_fs/inode.c	2013-11-11 17:56:58.000000000 +0200
+++ prl_fs/SharedFolders/Guest/Linux/prl_fs/inode.c	2013-11-29 20:41:53.689167040 +0200
@@ -199,10 +199,18 @@
 	if (attr->valid & _PATTR_MODE)
 		inode->i_mode = (inode->i_mode & S_IFMT) | (attr->mode & 0777);
 	if ((attr->valid & _PATTR_UID) &&
-	    (sbi->plain || sbi->share || attr->uid == -1))
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,5,0)
+	    (sbi->plain || sbi->share || __kuid_val(attr->uid) == -1))
+#else
+	    (sbi->plain || sbi->share || attr->uid == -1)))
+#endif
 		inode->i_uid = attr->uid;
 	if ((attr->valid & _PATTR_GID) &&
-	    (sbi->plain || sbi->share || attr->gid == -1))
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,5,0)
+	    (sbi->plain || sbi->share || __kgid_val(attr->gid) == -1))
+#else
+	    (sbi->plain || sbi->share || attr->gid == -1)))
+#endif
 		inode->i_gid = attr->gid;
 	return;
 }
@@ -521,13 +529,21 @@

 	generic_fillattr(dentry->d_inode, stat);
 	if (PRLFS_SB(dentry->d_sb)->share) {
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,5,0)
+		if (__kuid_val(stat->uid) != -1)
+#else
 		if (stat->uid != -1)
+#endif
 #if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,29)
 			stat->uid = current->fsuid;
 #else
 			stat->uid = current->cred->fsuid;
 #endif
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,5,0)
+		if (__kgid_val(stat->gid) != -1)
+#else
 		if (stat->gid != -1)
+#endif
 #if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,29)
 			stat->gid = current->fsgid;
 #else
@@ -577,9 +593,17 @@
 	mode = inode->i_mode;
 	isdir = S_ISDIR(mode);

+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,5,0)
+	if (__kuid_val(inode->i_uid) != -1)
+#else
 	if (inode->i_uid != -1)
+#endif
 		mode = mode >> 6;
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,5,0)
+	else if (__kgid_val(inode->i_gid) != -1)
+#else
 	else if (inode->i_gid != -1)
+#endif
 		mode = mode >> 3;
 	mode &= 0007;
 	mask &= MAY_READ | MAY_WRITE | MAY_EXEC;
diff -Nru prl_fs.orig/SharedFolders/Guest/Linux/prl_fs/prlfs.h prl_fs/SharedFolders/Guest/Linux/prl_fs/prlfs.h
--- prl_fs.orig/SharedFolders/Guest/Linux/prl_fs/prlfs.h	2013-11-11 17:56:58.000000000 +0200
+++ prl_fs/SharedFolders/Guest/Linux/prl_fs/prlfs.h	2013-11-29 20:46:27.662771996 +0200
@@ -28,8 +28,13 @@
 	struct	pci_dev *pdev;
 	unsigned sfid;
 	unsigned ttl;
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,5,0)
+	kuid_t uid;
+	kgid_t gid;
+#else
 	uid_t uid;
 	gid_t gid;
+#endif
 	int readonly;
 	int share;
 	int plain;
diff -Nru prl_fs.orig/SharedFolders/Guest/Linux/prl_fs/super.c prl_fs/SharedFolders/Guest/Linux/prl_fs/super.c
--- prl_fs.orig/SharedFolders/Guest/Linux/prl_fs/super.c	2013-11-11 17:56:58.000000000 +0200
+++ prl_fs/SharedFolders/Guest/Linux/prl_fs/super.c	2013-11-29 20:28:39.212000000 +0200
@@ -13,6 +13,7 @@
 #include <linux/seq_file.h>
 #include <linux/ctype.h>
 #include <linux/vfs.h>
+#include <linux/parser.h>
 #include "prlfs.h"
 #include "prlfs_compat.h"

@@ -26,38 +27,35 @@
 extern struct file_operations prlfs_names_fops;
 extern struct inode_operations prlfs_names_iops;

-static int prlfs_strtoui(char *cp, unsigned *result){
-	int ret = 0;
-	unsigned ui = 0;
-	unsigned digit;
-
-	if (!cp || (*cp == 0))
-		return -EINVAL;
-
-	while (*cp) {
-		if (isdigit(*cp)) {
-			digit = *cp - '0';
-		} else {
-			ret = -EINVAL;
-			break;
-		}
-		if (ui > ui * 10U + digit)
-			return -EINVAL;
-		ui = ui * 10U + digit;
-		cp++;
-	}
-
-	if (ret == 0)
-		*result = ui;
-
-	return ret;
-}
+enum {
+	Opt_uid,
+	Opt_gid,
+	Opt_ttl,
+	Opt_nls,
+	Opt_share,
+	Opt_plain,
+	Opt_sf,
+	Opt_err,
+};
+
+static const match_table_t prlfs_tokens = {
+	{Opt_uid, "uid=%d"},
+	{Opt_gid, "gid=%d"},
+	{Opt_ttl, "ttl=%u"},
+	{Opt_nls, "nls=%s"},
+	{Opt_share, "share"},
+	{Opt_plain, "plain"},
+	{Opt_sf, "sf=%s"},
+	{Opt_err, NULL}
+};

 static int
 prlfs_parse_mount_options(char *options, struct prlfs_sb_info *sbi)
 {
+	substring_t args[MAX_OPT_ARGS];
 	int ret = 0;
-	char *opt, *val;
+	int val;
+	char *opt;

 	DPRINTK("ENTER\n");
 #if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,29)
@@ -70,35 +68,54 @@
 	sbi->ttl = HZ;

 	if (!options)
-	       goto out;
+		goto out;

-	while (!ret && (opt = strsep(&options, ",")) != NULL)
+	while (!ret && ((opt = strsep(&options, ",")) != NULL))
 	{
+		int token;
 		if (!*opt)
 			continue;

-		val = strchr(opt, '=');
-		if (val) {
-			*(val++) = 0;
-			if (strlen(val) == 0)
-				val = NULL;
-		}
-		if (!strcmp(opt, "ttl") && val)
-			ret = prlfs_strtoui(val, &sbi->ttl);
-		else if (!strcmp(opt, "uid") && val)
-			ret = prlfs_strtoui(val, &sbi->uid);
-		else if (!strcmp(opt, "gid") && val)
-			ret = prlfs_strtoui(val, &sbi->gid);
-		else if (!strcmp(opt, "nls") && val)
-			strncpy(sbi->nls, val, LOCALE_NAME_LEN - 1);
-		else if (!strcmp(opt, "share"))
+		token = match_token(opt, prlfs_tokens, args);
+		switch (token) {
+		case Opt_uid:
+			if (!(ret = match_int(&args[0], &val)))
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,5,0)
+			sbi->uid = KUIDT_INIT(val);
+#else
+			sbi->uid = val;
+#endif
+			break;
+		case Opt_gid:
+			if (!(ret = match_int(&args[0], &val)))
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,5,0)
+			sbi->gid = KGIDT_INIT(val);
+#else
+			sbi->gid = val;
+#endif
+			break;
+		case Opt_ttl:
+			if (!(ret = match_int(&args[0], &val)))
+				sbi->ttl = val;
+			break;
+		case Opt_nls:
+			if (!match_strlcpy(sbi->nls, &args[0], LOCALE_NAME_LEN - 1))
+				ret = -EINVAL;
+			break;
+		case Opt_share:
 			sbi->share = 1;
-		else if (!strcmp(opt, "plain"))
+			break;
+		case Opt_plain:
 			sbi->plain = 1;
-		else if (!strcmp(opt, "sf") && val)
-			strncpy(sbi->name, val, sizeof(sbi->name));
-		else
+			break;
+		case Opt_sf:
+			if (!match_strlcpy(sbi->name, &args[0], sizeof(sbi->name)))
+				ret = -EINVAL;
+			break;
+		default:
 			ret = -EINVAL;
+		}
+		DPRINTK("PARSE interating %d:%d:%s\n", token, val, args[0]);
 	}
 out:
 	DPRINTK("EXIT returning %d\n", ret);
diff -Nru prl_fs.orig/SharedFolders/Interfaces/sf_lin.h prl_fs/SharedFolders/Interfaces/sf_lin.h
--- prl_fs.orig/SharedFolders/Interfaces/sf_lin.h	2013-11-11 18:11:49.000000000 +0200
+++ prl_fs/SharedFolders/Interfaces/sf_lin.h	2013-11-29 03:11:48.924415600 +0200
@@ -40,8 +40,13 @@
 	unsigned long long mtime;
 	unsigned long long ctime;
 	unsigned int mode;
-	unsigned int uid;
-	unsigned int gid;
+#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,5,0)
+	kuid_t uid;
+	kgid_t gid;
+#else
+	uid_t uid;
+	gid_t gid;
+#endif
 	unsigned int valid;
 } PACKED;
 SFLIN_CHECK_SIZE(prlfs_attr, sizeof(struct prlfs_attr), 48)
 EOF


# Patching
tar -xaf prl_mod.tar.gz
patch -p1 -d prl_fs < parallels-tools-linux-3.12-prl-fs-9.0.23350.941886.patch
tar -czf prl_mod.tar.gz prl_eth prl_fs prl_fs_freeze prl_tg Makefile.kmods dkms.conf

# Install normally
../install

# Ask
reboot
