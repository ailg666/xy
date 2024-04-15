//查看日志: "docker logs -f -n 10 emby-nginx 2>&1  | grep js:"
async function redirect2Pan(r) {
    //下面4个设置,通常来说保持默认即可,根据实际情况修改
    const embyHost = 'EMBY_SERVER'; //这里默认emby的地址是宿主机,要注意iptables给容器放行端口
    const embyMountPath = '/';  // rclone 的挂载目录, 例如将od, gd挂载到/mnt目录下:  /mnt/onedrive  /mnt/gd ,那么这里就填写 /mnt  
    const alistPwd = '56965779';      //alist password
    const alistApiPath = '_DOCKER_ADDRESS/'; //访问宿主机上5244端口的alist api, 要注意iptables给容器放行端口

    //fetch mount emby file path
    //const itemId = /[\d]+/.exec(r.uri)[0];
    const itemId = r.args.MediaSourceId;
    const mediaSourceId = r.args.MediaSourceId;
    let api_key = r.args.api_key;
    //let userid = '8192b61951e44c71bb67cc418f186c6b';
	let userid = '7c49d91c67e7478ca80af622373f08cc';
    //infuse用户需要填写下面的api_key, 感谢@amwamw968
    if ((api_key === null) || (api_key === undefined)) {
        //api_key = 'e825ed6f7f8f44ffa0563cddaddce14d';//这里填自己的API KEY
        api_key = 'INFUSE_API_KEY';//这里填自己的API KEY
        r.error(`api key for Infuse: ${api_key}`);
    }
    
    if(r.uri.indexOf("Subtitles")!=-1){
        r.internalRedirect("@backend");
        return;
    }
    const itemInfoUri = `${embyHost}/Items/${itemId}/PlaybackInfo?api_key=${api_key}&UserId=${userid}`;
    r.error(`itemInfoUri: ${itemInfoUri}`);
    let embyRes = await fetchEmbyFilePath(itemInfoUri, mediaSourceId);
    if (embyRes.startsWith('error')) {
        r.error(embyRes);
        r.return(500, embyRes);
        return;
    }
    r.error(`mount emby file path: ${embyRes}`);

    var doesNotContainHttp = !embyRes.includes("http");
    var doesNotContainDOCKER = !embyRes.includes("DOCKER_ADDRESS");
    if(doesNotContainHttp && doesNotContainDOCKER){
        r.warn(`跳转到本地链接`);
        r.internalRedirect("@backend");
        return;
    }

    if (embyRes.indexOf("/static/http")!=-1) {
        r.warn(`返回cd2链接: ${embyRes}`);
        r.return(302, `${(embyRes)}`);
        return;
    }

    //fetch alist direct link
    //const alistFilePath = embyRes.replace(embyMountPath, '');
    //const alistRes = await fetchAlistPathApi(alistApiPath, alistFilePath, alistPwd);
    const alistFilePath = embyRes.replace('DOCKER_ADDRESS', 'http://127.0.0.1:5678').replace('_DOCKER_ADDRESS', 'http://127.0.0.1:5678').replace('http://xiaoya.host:5678', 'http://127.0.0.1:5678');
    let alistRes = await fetchXYApi(`${alistFilePath}`);
    r.warn(`xiaoya容器返回: ${alistRes}`); 

       
    if (!alistRes.startsWith('error')) {
	if(alistRes.indexOf("http")!=-1){
		r.warn(`跳转到小雅链接: ${alistRes}`);
		r.return(302, alistRes);
		return;
	}
        if (alistRes.includes("object not found")) {
                r.warn(`strm 文件内路径错误，请检查资源是否被删除，或被更名`);
                r.return(302,"http://image.xiaoya.pro/404.mp4");
                return;
        }
        return;
    }
	
    if (alistRes.startsWith('error401')) {
        r.error(alistRes);
        r.return(401, alistRes);
        return;
    }
    if (alistRes.startsWith('error404')) {
        const filePath = alistFilePath.substring(alistFilePath.indexOf('/', 1));
        const foldersRes = await fetchAlistPathApi(alistApiPath, '/', alistPwd);
        if (foldersRes.startsWith('error')) {
            r.error(foldersRes);
            r.return(500, foldersRes);
            return;
        }
        const folders = foldersRes.split(',').sort();
        for (let i = 0; i < folders.length; i++) {
            r.error(`try to fetch alist path from /${folders[i]}${filePath}`);
            const driverRes = await fetchAlistPathApi(alistApiPath, `/${folders[i]}${filePath}`, alistPwd);
            if (!driverRes.startsWith('error')) {
                r.error(`redirect to: ${driverRes}`);
                r.return(302, driverRes);
                return;
            }
        }
        r.error(alistRes);
        r.return(404, alistRes);
        return;
    }
    r.error(alistRes);
    r.return(500, alistRes);
    return;
}

async function fetchAlistPathApi(alistApiPath, alistFilePath, alistPwd) {
    const alistRequestBody = {
        "path": alistFilePath,
        "password": alistPwd
    }
    try {
        const response = await ngx.fetch(alistApiPath, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json;charset=utf-8'
            },
            max_response_body_size: 365535,  
            body: JSON.stringify(alistRequestBody)
        })
        if (response.ok) {
            const result = await response.json();
            if (result === null || result === undefined) {
                return `error: alist_path_api response is null`;
            }
            if (result.message == 'success') {
                if (result.data.type == 'file') {
                    return result.data.files[0].url;
                }
                if (result.data.type == 'folder') {
                    return result.data.files.map(item => item.name).join(',');
                }
            }
            if (result.code == 401) {
                return `error401: alist_path_api ${result.message}`;
            }
            if (result.message.includes('account')) {
                return `error404: alist_path_api ${result.code} ${result.message}`;
            }
            if (result.message == 'path not found') {
                return `error404: alist_path_api ${result.message}`;
            }
            return `error: alist_path_api ${result.code} ${result.message}`;
        }
        else {
            return `error: alist_path_api ${response.status} ${response.statusText}`;
        }
    } catch (error) {
        return (`error: alist_path_api fetchAlistFiled ${error}`);
    }
}

async function fetchEmbyFilePath(itemInfoUri, mediaSourceId) {
    try {
        const res = await ngx.fetch(itemInfoUri, { max_response_body_size: 365535 });
        if (res.ok) {
            const result = await res.json();
            if (result === null || result === undefined) {
                return `error: emby_api itemInfoUri response is null`;
            }
            const mediaSource = result.MediaSources.find(m => m.Id == mediaSourceId);
            if (mediaSource === null || mediaSource === undefined) {
                return `error: emby_api mediaSourceId ${mediaSourceId} not found`;
            }
            return mediaSource.Path;
        }
        else {
            return (`error: emby_api ${res.status} ${res.statusText}`);
        }
    }
    catch (error) {
        return (`error: emby_api fetch mediaItemInfo failed,  ${error}`);
    }
}

async function fetchXYApi(xyurl) {
    try {                                 
        const res = await ngx.fetch(xyurl, { headers: { 'Content-Type': 'application/json;charset=utf-8' }, max_response_body_size: 365535} );
        if (res.status == 302) { 
            if (res.statusText == "Found") {                    
                return res.headers.Location;            
            }                                                 
            return (`error: xy_api return 304 destination is null`);
        }
        else {
		return res.text();
            //return (`error: xy_api return 302 failed: ${res.status} ${res.statusText}`);
        }                              
    }          
    catch (error) {
        return (`error: xy_api fetch aliyun direct link failed,  ${error}`);
    }                                                                                      
} 

export default { redirect2Pan };
