/*
 * Copyright (C) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  AbilityAware,
  AbilityPluginBinding
} from '@ohos/flutter_ohos';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import ResultMessage from './ResultMessage'
import { deviceInfo } from '@kit.BasicServicesKit';

const TAG = "ImageGallerySaverPlusPlugin";

/** ImageGallerySaverPlusPlugin **/
export default class ImageGallerySaverPlusPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;
  private imageType: Array<string> = ["png", "jpg", "jpeg", "gif"];
  private videoType: Array<string> = ["mp4", "mkv", "mov", "avi", "flv"]
  private savefileName: string = '';
  private savefileType: string = '';
  private isImage: boolean = false;
  private noFirstInvoke: boolean = false;

  constructor() {
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
    if (deviceInfo.sdkApiVersion >= 18) {
      let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
      phAccessHelper.getSupportedPhotoFormats(photoAccessHelper.PhotoType.IMAGE).then((res) => {
        this.imageType = res;
      }).catch(() => {
        console.error(`Unable to obtain the supported image format`);
      })
      phAccessHelper.getSupportedPhotoFormats(photoAccessHelper.PhotoType.VIDEO).then((res) => {
        this.videoType = res;
      }).catch(() => {
        console.error(`Unable to obtain the supported video format`);
      })
    }
  }

  onDetachedFromAbility(): void {
  }

  getUniqueClassName(): string {
    return "ImageGallerySaverPlusPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "image_gallery_saver_plus");
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
    }
  }


  async onMethodCall(call: MethodCall, result: MethodResult) {
    switch (call.method) {
      case "saveFileToGallery":
        if (this.noFirstInvoke) {
          return;
        }
        this.noFirstInvoke = true;
        let FileName: string = call.argument("name");
        let uri: string = call.argument("file");
        result.success(await this.saveFileToGallery(FileName, uri));
        this.noFirstInvoke = false;
        break;
      case "saveImageToGallery":
        if (this.noFirstInvoke) {
          return;
        }
        this.noFirstInvoke = true;
        let imageByte: Uint8Array = call.argument("imageBytes");
        let quality: number = call.argument("quality");
        let ImageName: string = call.argument("name");
        result.success(await this.saveImageToGallery(imageByte, quality, ImageName));
        this.noFirstInvoke = false;
        break;
      default:
        result.notImplemented();
    }
  }

  // 保存图片
  async saveImageToGallery(imageByte: Uint8Array, quality: number, name: string): Promise<ResultMessage> {
    if (this.context == null || this.context == undefined) {
      return new ResultMessage(null, "applicationContext is null", false);
    }
    let imageSource: image.ImageSource = image.createImageSource(imageByte.buffer);
    let packOpts: image.PackingOption = { format: "image/png", quality: quality };
    const filePath: string = this.context?.filesDir + "/imageLocal.png";
    let file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    const imagePackerObj: image.ImagePacker = image.createImagePacker();
    imagePackerObj.packToFile(imageSource, file.fd, packOpts, (err: BusinessError) => {
      if (err) {
        console.error(`Failed to pack the image to file.code ${err.code},message is ${err.message}`);
      } else {
        console.info('Succeeded in packing the image to file.');
      }
    })
    let photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [
      {
        title: name,
        fileNameExtension: "png",
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
      }
    ];
    return this.saveToPhoto(filePath, photoCreationConfigs);
  }

  // 保存文件
  async saveFileToGallery(name: string, uri: string): Promise<ResultMessage> {
    if (this.context == null || this.context == undefined) {
      return new ResultMessage(null, "applicationContext is null", false);
    }

    if (this.getNameType(uri, name) == -1) {
      return new ResultMessage(null, "Unsupported file type", false)
    }

    let isExist = await this.isFileExist(uri);
    if (isExist !== "file exists") {
      return new ResultMessage(null, isExist, false);
    }
    let photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [
      {
        title: this.savefileName,
        fileNameExtension: this.savefileType,
        photoType: this.isImage ? photoAccessHelper.PhotoType.IMAGE : photoAccessHelper.PhotoType.VIDEO,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
      }
    ];
    return this.saveToPhoto(uri, photoCreationConfigs);
  }

  // 保存至图库
  async saveToPhoto(uri: string,
    photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig>): Promise<ResultMessage> {
    let srcFileUris: Array<string> = [
      fileUri.getUriFromPath(uri)
    ];
    let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
    // 拉起弹窗
    let desFileUris: Array<string> = await phAccessHelper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
    if (desFileUris.length == 0) {
      return new ResultMessage(null, "user refuses permission", false);
    }
    let desFile: fs.File = await fs.open(desFileUris[0], fs.OpenMode.WRITE_ONLY);
    let srcFile: fs.File = await fs.open(uri, fs.OpenMode.READ_ONLY);
    let message = new ResultMessage(desFile.path, null, true);
    await fs.copyFile(srcFile.fd, desFile.fd);
    fs.closeSync(srcFile);
    fs.closeSync(desFile);
    return message;
  }

  // 文件是否存在
  async isFileExist(uri: string): Promise<string> {
    let isExist: string = '';
    await fs.access(uri).then((res) => {
      if (res) {
        isExist = "file exists";
        hilog.info(0, TAG, "file exists");
      }
    }).catch((err: BusinessError) => {
      isExist = err.message;
      hilog.info(0, TAG, "access failed with error message: " + err.message + ", error code: " + err.code);
    })
    return isExist;
  }

  // 返回保存文件名和类型 png、jpg、jpeg or video
  getNameType(uri: string, name: string): number {
    let fileName: string[];
    let result = uri.split("/");
    fileName = result[result.length-1].split(".");
    this.savefileName = fileName[0].toLowerCase();
    this.savefileType = fileName[1].toLowerCase();
    if (name !== null && name !== undefined) {
      fileName = name.split(".");
      switch (fileName.length) {
        case 2:
          this.savefileName = fileName[0].toLowerCase();
          this.savefileType = fileName[1].toLowerCase();
          break;
        case 1:
          this.savefileName = fileName[0].toLowerCase();
          break;
      }
    }
    let imageFlag = this.imageType.indexOf(this.savefileType)
    let videoFlag = this.videoType.indexOf(this.savefileType)
    let flag: number = 0
    if (imageFlag == -1 && videoFlag == -1) {
      flag = -1
    } else if (imageFlag != -1) {
      this.isImage = true
    } else if (videoFlag != -1) {
      this.isImage = false
    }
    return flag
  }
}